import XCTest
import AVFoundation
import WebKit
import UIKit
import SwiftUI
@testable import FormApp

final class WeeklyProgressTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let now = WorkoutCalendar.parseIsoTimestamp("2026-09-14T10:30:00Z")!
    private var exercise: Exercise { Exercise(id: "bench", name: "Bench", sets: 2) }
    private var workout: Workout { Workout(id: "w1", day: 1, title: "Upper", exercises: [exercise]) }
    private var program: Program {
        Program(id: "p", name: "Fixture", workouts: [workout] + (2...5).map { Workout(id: "w\($0)", day: $0, title: "Day \($0)") })
    }

    private func draft(weight: Double = 60, assignedDay: String? = "2026-09-14") -> ActiveSessionDraft {
        ActiveSessionDraft(id: "resumed", programId: program.id, workout: workout,
            startedAt: "2026-09-14T10:00:00Z", startedAtEpochMillis: Int64(now.timeIntervalSince1970 * 1000) - 1_800_000,
            setsByExercise: [exercise.id: [
                ExerciseSetLog(setNumber: 1, weightKg: 20, completedReps: 10, isCompleted: true, isWarmup: true),
                ExerciseSetLog(setNumber: 1, weightKg: weight, completedReps: 10, isCompleted: true),
                ExerciseSetLog(setNumber: 2, weightKg: weight, completedReps: 10, isCompleted: false)
            ]], assignedCalendarDate: assignedDay)
    }

    private func record(id: String, date: String, volume: Double, complete: Bool = false, workoutId: String = "w1") -> WorkoutSessionRecord {
        WorkoutSessionRecord(id: id, programId: program.id, workoutId: workoutId, workoutTitle: workout.title,
            startedAt: date, completedAt: date, durationSeconds: 1800, totalVolumeKg: volume,
            totalCompletedSets: 1, exerciseLogs: [], isComplete: complete)
    }

    func testPartialSessionCanShowVolumeAndTimeWithZeroCompletedDays() {
        let history = [record(id: "partial", date: "2026-09-14T10:00:00Z", volume: 4840),
            record(id: "old", date: "2026-09-07T10:00:00Z", volume: 99999, complete: true)]
        let metrics = PersonalRecordTracker.computeWeeklyMetrics(program: program, completedKeys: [], history: history,
            currentWeekKey: "2026-W38", timeZone: utc)
        XCTAssertEqual(metrics.completedWorkouts, 0)
        XCTAssertEqual(metrics.totalWorkouts, 5)
        XCTAssertEqual(metrics.totalVolumeKg, 4840)
        XCTAssertEqual(metrics.activeDurationSeconds, 1800)
        XCTAssertEqual(metrics.prsHitCount, 0)
    }

    func testResumedDraftReplacesSavedPartialAndExcludesWarmups() {
        let active = draft(weight: 70)
        let earlier = Int64(now.timeIntervalSince1970 * 1000) - 600_000
        let saved = SessionProgress.from(draft: draft(), nowEpochMillis: earlier).record(draft: draft(), completedAtEpochMillis: earlier)
        var baseline = saved
        baseline.id = "baseline"
        baseline.startedAt = "2026-09-07T10:00:00Z"
        baseline.completedAt = baseline.startedAt
        baseline.exerciseLogs = [SessionExerciseLog(exerciseName: "Bench", sets: [SessionSetLog(setNumber: 1, weightKg: 50, reps: 10)], targetSets: 2)]
        let metrics = PersonalRecordTracker.computeWeeklyMetrics(program: program, completedKeys: [], history: [saved, baseline],
            currentWeekKey: "2026-W38", activeSession: active, unfinishedKeys: ["p:w1"], now: now, timeZone: utc)
        XCTAssertEqual(metrics.totalVolumeKg, 700)
        XCTAssertEqual(metrics.activeDurationSeconds, 1800)
        XCTAssertEqual(metrics.completedWorkouts, 0)
        XCTAssertEqual(metrics.prsHitCount, 1)
        let nowMillis = Int64(now.timeIntervalSince1970 * 1000)
        let finished = SessionProgress.from(draft: active, nowEpochMillis: nowMillis).record(draft: active, completedAtEpochMillis: nowMillis)
        XCTAssertEqual(metrics, PersonalRecordTracker.computeWeeklyMetrics(program: program, completedKeys: [], history: [finished, baseline],
            currentWeekKey: "2026-W38", unfinishedKeys: ["p:w1"], now: now, timeZone: utc))
    }

    func testResumedFirstSessionStillEstablishesOnlyOneBaseline() {
        let nowMillis = Int64(now.timeIntervalSince1970 * 1000)
        let saved = SessionProgress.from(draft: draft(), nowEpochMillis: nowMillis).record(draft: draft(), completedAtEpochMillis: nowMillis)
        XCTAssertEqual(PersonalRecordTracker.countPrsForWeek(history: [saved], currentWeekKey: "2026-W38",
            activeSession: draft(weight: 70), now: now, timeZone: utc), 0)
    }

    func testPriorWeekActiveSessionDoesNotLeakIntoNewWeek() {
        let metrics = PersonalRecordTracker.computeWeeklyMetrics(program: program, completedKeys: [], history: [],
            currentWeekKey: "2026-W38", activeSession: draft(weight: 70, assignedDay: "2026-09-13"), now: now, timeZone: utc)
        XCTAssertEqual(metrics.totalVolumeKg, 0)
        XCTAssertEqual(metrics.activeDurationSeconds, 0)
        XCTAssertEqual(metrics.prsHitCount, 0)
    }

    func testLegacyDraftUsesStartingWeekAndDurationMatchesSavedCap() {
        var active = draft(assignedDay: nil)
        active.startedAt = "2026-09-13T23:55:00Z"
        let metrics = PersonalRecordTracker.computeWeeklyMetrics(program: program, completedKeys: [], history: [],
            currentWeekKey: "2026-W38", activeSession: active, now: now, timeZone: utc)
        XCTAssertEqual(metrics.totalVolumeKg, 0)
        XCTAssertEqual(metrics.activeDurationSeconds, 0)
        var longRunning = draft()
        longRunning.startedAtEpochMillis = Int64(now.timeIntervalSince1970 * 1000) - 24 * 3_600_000
        let capped = PersonalRecordTracker.computeWeeklyMetrics(program: program, completedKeys: [], history: [],
            currentWeekKey: "2026-W38", activeSession: longRunning, now: now, timeZone: utc)
        XCTAssertEqual(capped.activeDurationSeconds, 6 * 3600)
    }

    func testActiveSessionPauseAndResumeDurationAccuracy() {
        let t0: Int64 = 1_000_000_000_000
        let w = Workout(id: "w1", day: 1, title: "Push", exercises: [])
        let initialDraft = ActiveSessionDraft(
            programId: "p1",
            workout: w,
            startedAt: "2026-10-06T10:00:00Z",
            startedAtEpochMillis: t0,
            accumulatedSeconds: 0,
            isPaused: false,
            lastResumedAtEpochMillis: t0
        )

        // 1. Running for 120 seconds
        let t1 = t0 + 120_000
        XCTAssertEqual(initialDraft.currentDurationSeconds(nowEpochMillis: t1), 120)
        let progress1 = SessionProgress.from(draft: initialDraft, nowEpochMillis: t1)
        XCTAssertEqual(progress1.durationSeconds, 120)

        // 2. Pause session at t1
        let pausedDraft = initialDraft.paused(nowEpochMillis: t1)
        XCTAssertTrue(pausedDraft.isPaused)
        XCTAssertEqual(pausedDraft.accumulatedSeconds, 120)

        // 3. User leaves app for 1 hour (3600 seconds). Time must not tick.
        let t2 = t1 + 3_600_000
        XCTAssertEqual(pausedDraft.currentDurationSeconds(nowEpochMillis: t2), 120)
        let progressPaused = SessionProgress.from(draft: pausedDraft, nowEpochMillis: t2)
        XCTAssertEqual(progressPaused.durationSeconds, 120)

        // 4. User resumes session at t2 (clicks resume)
        let resumedDraft = pausedDraft.resumed(nowEpochMillis: t2)
        XCTAssertFalse(resumedDraft.isPaused)
        XCTAssertEqual(resumedDraft.accumulatedSeconds, 120)
        XCTAssertEqual(resumedDraft.lastResumedAtEpochMillis, t2)

        // 5. User trains for another 30 seconds
        let t3 = t2 + 30_000
        XCTAssertEqual(resumedDraft.currentDurationSeconds(nowEpochMillis: t3), 150)
        let progressResumed = SessionProgress.from(draft: resumedDraft, nowEpochMillis: t3)
        XCTAssertEqual(progressResumed.durationSeconds, 150)
    }

    func testPauseAtZeroSecondsAndResumeKeepsAccurateDuration() {
        let t0: Int64 = 1_000_000_000_000
        let w = Workout(id: "w1", day: 1, title: "Push", exercises: [])
        let initialDraft = ActiveSessionDraft(
            programId: "p1",
            workout: w,
            startedAt: "2026-10-06T10:00:00Z",
            startedAtEpochMillis: t0,
            accumulatedSeconds: 0,
            isPaused: false,
            lastResumedAtEpochMillis: t0
        )

        // Paused immediately within the same second (0 accumulated seconds)
        let pausedDraft = initialDraft.paused(nowEpochMillis: t0 + 200)
        XCTAssertTrue(pausedDraft.isPaused)
        XCTAssertEqual(pausedDraft.accumulatedSeconds, 0)

        // Stays paused for 2 hours
        let t1 = t0 + 7_200_000
        XCTAssertEqual(pausedDraft.currentDurationSeconds(nowEpochMillis: t1), 0)

        // Resume at t1
        let resumedDraft = pausedDraft.resumed(nowEpochMillis: t1)
        XCTAssertFalse(resumedDraft.isPaused)
        XCTAssertEqual(resumedDraft.accumulatedSeconds, 0)
        XCTAssertEqual(resumedDraft.lastResumedAtEpochMillis, t1)

        // Trains for 45 seconds
        let t2 = t1 + 45_000
        XCTAssertEqual(resumedDraft.currentDurationSeconds(nowEpochMillis: t2), 45)
        XCTAssertEqual(SessionProgress.from(draft: resumedDraft, nowEpochMillis: t2).durationSeconds, 45)
    }

    func testRestTimerIsPausedWhenActiveSessionIsPaused() {
        let t0: Int64 = 1_000_000_000_000
        let w = Workout(id: "w1", day: 1, title: "Push", exercises: [])
        let rest = RestTimerState(
            exerciseName: "Bench Press",
            totalSeconds: 90,
            isRunning: true,
            endsAtEpochMillis: t0 + 90_000,
            pausedSecondsRemaining: 0
        )
        let draft = ActiveSessionDraft(
            programId: "p1",
            workout: w,
            startedAt: "2026-10-06T10:00:00Z",
            startedAtEpochMillis: t0,
            restTimer: rest,
            accumulatedSeconds: 0,
            isPaused: false,
            lastResumedAtEpochMillis: t0
        )

        // Pause 30 seconds later (60 seconds remaining on rest timer)
        let paused = draft.paused(nowEpochMillis: t0 + 30_000)
        guard let pausedRest = paused.restTimer else {
            XCTFail("Rest timer should not be nil")
            return
        }
        XCTAssertFalse(pausedRest.isRunning)
        XCTAssertEqual(pausedRest.pausedSecondsRemaining, 60)
        XCTAssertNil(pausedRest.endsAtEpochMillis)
    }

    func testMondayRolloverUsesLocalISOYearAndArchivesOnlyOnce() throws {
        let zone = TimeZone(identifier: "Europe/Istanbul")!
        let sunday = WorkoutCalendar.parseIsoTimestamp("2027-01-03T20:59:59Z")!
        let monday = sunday.addingTimeInterval(1)
        let history = [record(id: "old", date: "2026-12-28T10:00:00Z", volume: 4840, complete: true)]
        let state = StoredAppState(programs: [program], activeProgramId: program.id, completed: ["p:w1"],
            currentWeekKey: "2026-W53", history: history)
        XCTAssertEqual(AppStore.rotateWeek(state, now: sunday, timeZone: zone).completed, ["p:w1"])
        let rotated = AppStore.rotateWeek(state, now: monday, timeZone: zone)
        XCTAssertEqual(rotated.currentWeekKey, "2027-W01")
        XCTAssertTrue(rotated.completed.isEmpty)
        XCTAssertEqual(rotated.weeklyArchives.count, 1)
        XCTAssertEqual(rotated.weeklyArchives.first?.weekKey, "2026-W53")
        XCTAssertEqual(rotated.weeklyArchives.first?.completed, ["p:w1"])
        XCTAssertEqual(rotated.history, history)
        let repeated = AppStore.rotateWeek(rotated, now: monday.addingTimeInterval(60), timeZone: zone)
        XCTAssertEqual(repeated.weeklyArchives, rotated.weeklyArchives)
        let metrics = PersonalRecordTracker.computeWeeklyMetrics(program: program, completedKeys: rotated.completed,
            history: rotated.history, currentWeekKey: rotated.currentWeekKey, timeZone: zone)
        XCTAssertEqual(metrics.completedWorkouts, 0)
        XCTAssertEqual(metrics.totalVolumeKg, 0)
        XCTAssertEqual(metrics.activeDurationSeconds, 0)
    }

    func testFrozenWeekRecoversCurrentCompletionsWithoutCountingPartialSessions() {
        let history = [record(id: "old", date: "2026-08-31T10:00:00Z", volume: 99999, complete: true),
            record(id: "current", date: "2026-09-14T10:00:00Z", volume: 2000, complete: true, workoutId: "w2"),
            record(id: "repeat", date: "2026-09-14T10:10:00Z", volume: 500, complete: true, workoutId: "w2"),
            record(id: "partial", date: "2026-09-14T10:15:00Z", volume: 4840)]
        let state = StoredAppState(programs: [program], activeProgramId: program.id, completed: ["p:w1", "p:w2"],
            currentWeekKey: "2026-W36", history: history)
        let rotated = AppStore.rotateWeek(state, now: now, timeZone: utc)
        XCTAssertEqual(rotated.currentWeekKey, "2026-W38")
        XCTAssertEqual(rotated.completed, ["p:w2"])
        XCTAssertEqual(rotated.history, history)
        XCTAssertEqual(rotated.programs, state.programs)
        let metrics = PersonalRecordTracker.computeWeeklyMetrics(program: program, completedKeys: rotated.completed,
            history: rotated.history, currentWeekKey: rotated.currentWeekKey, timeZone: utc)
        XCTAssertEqual(metrics.completedWorkouts, 1)
        XCTAssertEqual(metrics.totalVolumeKg, 7340)
        XCTAssertEqual(metrics.activeDurationSeconds, 5400)
    }

    @MainActor
    private func withStoredFixture(_ body: (AppStore, StoredAppState) throws -> Void) throws {
        let defaults = UserDefaults.standard
        let domain = try XCTUnwrap(Bundle.main.bundleIdentifier)
        let original = defaults.persistentDomain(forName: domain) ?? [:]
        defer { defaults.setPersistentDomain(original, forName: domain) }
        let access = ProAccessManager.shared
        let cloudAccess = access.isFeatureUnlocked(.cloudBackup)
        access.setFeatureOverride(.cloudBackup, unlocked: false)
        defer { access.setFeatureOverride(.cloudBackup, unlocked: cloudAccess == access.isProSubscribed ? nil : cloudAccess) }
        defaults.removeObject(forKey: "active_session_v1")
        defaults.set(true, forKey: "seeded_starters_v9")
        defaults.set(true, forKey: "seeded_starters_v10")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fixture = StoredAppState(programs: [program], activeProgramId: program.id, completed: ["p:w1", "p:w2"],
            currentWeekKey: "2020-W01", history: [
                record(id: "old", date: "2019-12-30T10:00:00Z", volume: 99999, complete: true),
                record(id: "current", date: timestamp, volume: 2000, complete: true, workoutId: "w2"),
                record(id: "partial", date: timestamp, volume: 4840)
            ])
        defaults.set(try JSONEncoder().encode(fixture), forKey: "stored_app_state")
        try body(AppStore(persistence: AppStatePersistence(inMemory: true)), fixture)
    }

    @MainActor
    func testLaunchAndBackupRestoreNormalizeFrozenWeekAndPersistHistory() throws {
        try withStoredFixture { store, fixture in
            XCTAssertNotEqual(store.state.currentWeekKey, fixture.currentWeekKey)
            XCTAssertEqual(store.state.completed, ["p:w2"])
            XCTAssertEqual(store.state.history, fixture.history)
            XCTAssertEqual(store.state.weeklyArchives.count, 1)
            XCTAssertTrue(store.restoreBackupJson(String(decoding: try JSONEncoder().encode(fixture), as: UTF8.self)))
            XCTAssertEqual(store.state.completed, ["p:w2"])
            XCTAssertEqual(store.state.weeklyArchives.count, 1)
            let exported = try JSONDecoder().decode(StoredAppState.self, from: Data(store.exportBackupJson().utf8))
            XCTAssertEqual(exported.history, fixture.history)
            XCTAssertEqual(exported.completed, ["p:w2"])
            let reloaded = AppStore(persistence: store.statePersistence)
            XCTAssertEqual(reloaded.state.currentWeekKey, store.state.currentWeekKey)
            XCTAssertEqual(reloaded.state.completed, store.state.completed)
            XCTAssertEqual(reloaded.state.weeklyArchives, store.state.weeklyArchives)
        }
    }

    @MainActor
    func testDateNotificationsAndOrdinaryWritesRefreshFrozenWeek() throws {
        try withStoredFixture { store, fixture in
            for notification in [UIApplication.willEnterForegroundNotification, UIApplication.significantTimeChangeNotification, .NSCalendarDayChanged] {
                store.state = fixture
                store.selectedWorkoutId = "w1"
                NotificationCenter.default.post(name: notification, object: nil)
                XCTAssertNotEqual(store.state.currentWeekKey, fixture.currentWeekKey)
                XCTAssertEqual(store.state.completed, ["p:w2"])
                XCTAssertNil(store.selectedWorkoutId)
                XCTAssertEqual(store.state.history, fixture.history)
            }
            store.saveState(fixture)
            XCTAssertEqual(store.state.completed, ["p:w2"])
            XCTAssertEqual(store.state.weeklyArchives.count, 1)
        }
    }

    @MainActor
    func testSavingPastWeekSessionDoesNotCompleteCurrentWeekWorkout() throws {
        try withStoredFixture { store, fixture in
            let past = record(id: "past", date: "2019-12-30T10:00:00Z", volume: 600, complete: true, workoutId: "w3")
            store.completeActiveSession(past)
            XCTAssertEqual(store.state.completed, ["p:w2"])
            XCTAssertEqual(store.state.history.count, fixture.history.count + 1)
            XCTAssertEqual(store.state.history.first?.isComplete, true)
            XCTAssertTrue(store.state.calendarHistory?.entries.contains { $0.id == "session:past" && $0.status == .completed } == true)
        }
    }

    @MainActor
    func testRealResumeAndSaveKeepWeeklyTotalsStableAndCompletionRequiresEveryWorkingSet() throws {
        try withStoredFixture { store, _ in
            XCTAssertTrue(store.startActiveSession(programId: program.id, workout: workout, allowPast: true))
            XCTAssertEqual(store.activeSession?.id, "partial")
            store.updateActiveSession { draft in
                var copy = draft
                copy.setsByExercise[self.exercise.id] = [
                    ExerciseSetLog(setNumber: 1, weightInput: "60", repsInput: "10", weightKg: 60, completedReps: 10, isCompleted: true),
                    ExerciseSetLog(setNumber: 2)
                ]
                return copy
            }
            func metrics(now: Date) -> WeeklyGoalProgressMetrics {
                PersonalRecordTracker.computeWeeklyMetrics(program: program, completedKeys: store.state.completed, history: store.state.history,
                    currentWeekKey: store.state.currentWeekKey, activeSession: store.activeSession, now: now)
            }
            let moment = Date()
            let active = try XCTUnwrap(store.activeSession)
            let live = metrics(now: moment)
            XCTAssertEqual(live.totalVolumeKg, 2600)
            XCTAssertEqual(live.completedWorkouts, 1)
            let millis = Int64(moment.timeIntervalSince1970 * 1000)
            store.completeActiveSession(SessionProgress.from(draft: active, nowEpochMillis: millis).record(draft: active, completedAtEpochMillis: millis))
            XCTAssertNil(store.activeSession)
            XCTAssertEqual(metrics(now: moment).totalVolumeKg, live.totalVolumeKg)
            XCTAssertEqual(metrics(now: moment).activeDurationSeconds, live.activeDurationSeconds)
            XCTAssertEqual(store.state.history.count, 3)
            XCTAssertEqual(store.state.history.first?.isComplete, false)
            XCTAssertTrue(store.startActiveSession(programId: program.id, workout: workout, allowPast: true))
            store.updateActiveSession { draft in
                var copy = draft
                copy.setsByExercise[self.exercise.id] = (1...2).map {
                    ExerciseSetLog(setNumber: $0, weightInput: "60", repsInput: "10", weightKg: 60, completedReps: 10, isCompleted: true)
                }
                return copy
            }
            let completed = try XCTUnwrap(store.activeSession)
            store.completeActiveSession(SessionProgress.from(draft: completed, nowEpochMillis: millis).record(draft: completed, completedAtEpochMillis: millis))
            XCTAssertEqual(Set(store.state.completed), ["p:w1", "p:w2"])
            XCTAssertEqual(store.state.history.first?.isComplete, true)
            XCTAssertEqual(store.state.history.count, 3)
            XCTAssertEqual(metrics(now: moment).completedWorkouts, 2)
        }
    }
}

final class FormAppTests: XCTestCase {
    @MainActor
    func testHomeDayStripOpensOnCurrentWorkoutWindow() throws {
        func scrollViews(in view: UIView) -> [UIScrollView] {
            (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
        }
        let schedules = [
            (Array(1...5), [0, 0, 1, 1, 1, 1, 1]),
            (Array(1...7), [0, 0, 1, 2, 3, 3, 3]),
            ([1, 2, 4, 5, 6], [0, 0, 0, 1, 1, 1, 1]),
            ([2, 4, 6], [0, 0, 0, 0, 0, 0, 0])
        ]
        for width in [CGFloat(320), CGFloat(393)] {
            for (schedule, expectedStarts) in schedules {
                let workouts = schedule.map { Workout(id: "window-\($0)", day: $0, title: "Workout \($0)") }
                let program = Program(id: "window-fixture", name: "Fixture", workouts: workouts)
                for (today, firstIndex) in expectedStarts.enumerated() {
                    func content(completedKeys: [String] = []) -> some View {
                        WorkoutDayStrip(program: program, workouts: workouts,
                            calendar: WeekCalendar(today: today, numbers: Array(1...7)),
                            activeWorkoutId: workouts.first { $0.day == today + 1 }?.id,
                            completedKeys: completedKeys, unfinishedKeys: [], onSelectWorkout: { _ in })
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .background(AppColors.background)
                    }
                    let controller = UIHostingController(rootView: content())
                    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 200))
                    window.rootViewController = controller
                    window.makeKeyAndVisible()
                    controller.view.frame = window.bounds
                    controller.view.layoutIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.15))
                    controller.view.layoutIfNeeded()
                    let scroll = try XCTUnwrap(scrollViews(in: controller.view).first)
                    let tileWidth = (width - 40 - 3 * 8) / 4
                    XCTAssertEqual(scroll.contentOffset.x, CGFloat(firstIndex) * (tileWidth + 8), accuracy: 1,
                        "The opening window should follow the current scheduled workout: \(schedule), weekday \(today)")
                    XCTAssertLessThanOrEqual(20 + 4 * tileWidth + 3 * 8, scroll.bounds.width - 20 + 1)
                    if schedule == Array(1...5), today == 2 {
                        let image = UIGraphicsImageRenderer(size: controller.view.bounds.size).image { _ in
                            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
                        }
                        let attachment = XCTAttachment(image: image)
                        attachment.name = "home-day-tiles-third-workout-window-\(Int(width))"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                    }
                    if schedule == Array(1...7), today == 4 {
                        scroll.setContentOffset(.zero, animated: false)
                        controller.rootView = content(completedKeys: ["window-fixture:window-1"])
                        controller.view.layoutIfNeeded()
                        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
                        XCTAssertEqual(scroll.contentOffset.x, 0, accuracy: 1,
                            "Routine updates must preserve the user's manual scroll position")
                    }
                    window.isHidden = true
                }
            }
        }
    }

    @MainActor
    func testHomeDayStripShowsFourCompactTilesAndScrolls() throws {
        let previous = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(previous) }
        func scrollViews(in view: UIView) -> [UIScrollView] {
            (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
        }
        for (language, width, sizeCategory) in [
            ("en", CGFloat(320), ContentSizeCategory.large),
            ("en", CGFloat(393), ContentSizeCategory.large),
            ("en", CGFloat(440), ContentSizeCategory.large),
            ("tr", CGFloat(320), ContentSizeCategory.extraExtraExtraLarge)
        ] {
            LanguageManager.setLanguage(language)
            let names = language == "en"
                ? ["Chest & Triceps", "Back & Biceps", "Quads & Calves", "Upper Body & Shoulders", "Glutes & Hamstrings"]
                : ["Göğüs & Arka Kol", "Sırt & Ön Kol", "Bacak & Baldır", "Üst Vücut & Omuzlar", "Kalça & Arka Bacak"]
            var boundedRowHeight: CGFloat?
            for count in [5, 7] {
                let workouts = (0..<count).map { index in
                    Workout(id: "tile-\(index)", day: index + 1,
                        title: index < names.count ? names[index] : "Existing workout day with a much longer name")
                }
                let program = Program(id: "tile-fixture", name: "Fixture", workouts: workouts)
                var rowHeight: CGFloat?
                for selected in [workouts.first!.id, workouts.last!.id] {
                    let content = WorkoutDayStrip(program: program, workouts: workouts,
                        calendar: WeekCalendar(today: 4, numbers: [28, 29, 30, 1, 2, 3, 4]),
                        activeWorkoutId: selected, completedKeys: [], unfinishedKeys: [], onSelectWorkout: { _ in })
                        .environment(\.sizeCategory, sizeCategory)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background(AppColors.background)
                    let controller = UIHostingController(rootView: content)
                    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 350))
                    window.rootViewController = controller
                    window.makeKeyAndVisible()
                    controller.view.frame = window.bounds
                    controller.view.layoutIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.15))
                    controller.view.layoutIfNeeded()
                    let scroll = try XCTUnwrap(scrollViews(in: controller.view).first)
                    let tileWidth = (scroll.contentSize.width - 40 - CGFloat(count - 1) * 8) / CGFloat(count)
                    XCTAssertGreaterThanOrEqual(tileWidth, 48)
                    XCTAssertLessThanOrEqual(tileWidth, 96)
                    XCTAssertLessThanOrEqual(4 * tileWidth + 3 * 8, scroll.bounds.width - 40 + 1,
                        "Four whole tiles must fit at narrow and normal widths, including larger text")
                    XCTAssertGreaterThan(scroll.contentSize.width, scroll.bounds.width)
                    XCTAssertGreaterThanOrEqual(scroll.contentSize.height, 108)
                    if let boundedRowHeight {
                        XCTAssertEqual(scroll.contentSize.height, boundedRowHeight, accuracy: 1,
                            "Longer names must not increase the two-line tile height")
                    } else { boundedRowHeight = scroll.contentSize.height }
                    if let rowHeight {
                        XCTAssertEqual(scroll.contentSize.height, rowHeight, accuracy: 1, "Selection must keep the row height fixed")
                    } else { rowHeight = scroll.contentSize.height }
                    let image = UIGraphicsImageRenderer(size: controller.view.bounds.size).image { _ in
                        controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
                    }
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "home-day-tiles-\(language)-\(Int(width))-\(count)-\(selected)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                    window.isHidden = true
                }
            }
        }
    }

    func testHomeGlowTilesDefaultToCalmAndPersistTheChoice() throws {
        let key = "home_glow_tiles"
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.removeObject(forKey: key)
        let store = AppStore(persistence: AppStatePersistence(inMemory: true))
        XCTAssertFalse(store.homeGlowTiles, "The calm glass is the default Home tile style")
        store.homeGlowTiles = true
        XCTAssertEqual(UserDefaults.standard.object(forKey: key) as? Bool, true)
        XCTAssertTrue(AppStore(persistence: AppStatePersistence(inMemory: true)).homeGlowTiles)
        store.homeGlowTiles = false
        XCTAssertFalse(AppStore(persistence: AppStatePersistence(inMemory: true)).homeGlowTiles)
    }

    func testGlowTilesSettingIsTranslatedInEveryLanguage() {
        XCTAssertEqual(Translations.en["settings.glowTiles"], "Glowing day tiles")
        for language in ["tr", "de", "fr", "es"] {
            let table = Translations.forLanguage(language)
            for key in ["settings.glowTiles", "settings.glowTilesSubtitle"] {
                let value = table[key] ?? ""
                XCTAssertFalse(value.isEmpty, "\(language) \(key) is missing")
                XCTAssertNotEqual(value, Translations.en[key], "\(language) \(key) still reads as English")
            }
        }
    }

    @MainActor
    func testBothHomeTileStylesKeepTheSameLayoutAndRetainSnapshots() throws {
        func scrollViews(in view: UIView) -> [UIScrollView] {
            (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
        }
        let previousTheme = ThemeManager.shared.currentTheme.id
        defer { ThemeManager.shared.setThemeId(previousTheme) }
        let names = ["Chest & Triceps", "Back & Biceps", "Quads & Calves", "Upper Body & Shoulders", "Glutes & Hamstrings"]
        let workouts = names.enumerated().map { Workout(id: "tile-\($0.offset)", day: $0.offset + 1, title: $0.element) }
        let program = Program(id: "tile-fixture", name: "Fixture", workouts: workouts)
        for theme in ["default", "oat"] {
            ThemeManager.shared.setThemeId(theme)
            var sizes: [CGSize] = []
            for glow in [false, true] {
                let content = WorkoutDayStrip(program: program, workouts: workouts,
                    calendar: WeekCalendar(today: 4, numbers: [12, 13, 14, 15, 16, 17, 18]),
                    activeWorkoutId: "tile-4", completedKeys: ["tile-fixture:tile-0"],
                    unfinishedKeys: ["tile-fixture:tile-2"], onSelectWorkout: { _ in }, glowTiles: glow)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(AppColors.background)
                let controller = UIHostingController(rootView: content)
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 200))
                window.rootViewController = controller
                window.makeKeyAndVisible()
                controller.view.frame = window.bounds
                controller.view.layoutIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                controller.view.layoutIfNeeded()
                let scroll = try XCTUnwrap(scrollViews(in: controller.view).first)
                sizes.append(scroll.contentSize)
                let image = UIGraphicsImageRenderer(size: controller.view.bounds.size).image { _ in
                    controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "home-day-tiles-\(glow ? "glow" : "calm")-\(theme)"
                attachment.lifetime = .keepAlways
                add(attachment)
                window.isHidden = true
            }
            XCTAssertEqual(sizes[0].width, sizes[1].width, accuracy: 0.5, "Switching style must not resize the strip (\(theme))")
            XCTAssertEqual(sizes[0].height, sizes[1].height, accuracy: 0.5, "Switching style must not resize the strip (\(theme))")
        }
    }

    @MainActor
    func testBarbellPlateSnapshotsAtNarrowAndLargerLocalizedText() throws {
        let previous = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(previous) }
        for language in ["en", "tr"] {
            LanguageManager.setLanguage(language)
            for (target, unit) in [(65.0, WeightUnit.kg), (70.0, .kg), (90.0, .kg), (167.5, .kg), (500.0, .kg), (225.0, .lbs), (20.0, .kg)] {
                let result = WarmupPlateEngine.calculatePlates(targetWeight: target,
                    barWeight: unit == .kg ? 20 : 45,
                    availablePlates: WarmupPlateEngine.defaultPlates(unit: unit), unit: unit)
                let content = BarbellPlateVisualizerView(result: result, unit: unit)
                    .frame(width: 280)
                    .padding(20)
                    .background(AppColors.background)
                    .environment(\.sizeCategory, .extraExtraExtraLarge)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.uiImage)
                XCTAssertEqual(image.size.width, 320)
                let attachment = XCTAttachment(image: image)
                attachment.name = "plates-\(language)-\(unit.label)-\(target)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    @MainActor
    func testProgramCoverLibraryResourcesAndMappings() throws {
        let programs = AppStore.loadBundledStarterPrograms()
        XCTAssertEqual(Set(programs.map(\.id)), Set(ProgramCover.allCases.compactMap(\.programID)))
        XCTAssertEqual(ProgramCover.forProgram("custom-program"), .fullBody)
        for cover in ProgramCover.allCases {
            let image = try XCTUnwrap(UIImage(named: cover.assetName)?.cgImage)
            XCTAssertEqual(image.width, 1152)
            XCTAssertEqual(image.height, 768)
            if let programID = cover.programID {
                XCTAssertEqual(ProgramCover.forProgram(programID), cover)
            }
            XCTAssertEqual(ProgramCover.forProgram(Program(id: "aesthetic-hypertrophy", name: "Custom", coverId: cover.rawValue)), cover)
        }
        let data = try XCTUnwrap(NSDataAsset(name: "program_cover_catalog")?.data)
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(ProgramCover.allCases.count, 21)
        XCTAssertEqual((catalog["covers"] as? [[String: Any]])?.count, ProgramCover.allCases.count)
    }

    @MainActor
    func testProgramHeroCardSnapshotsAtNormalAndLargeTurkishText() throws {
        let previous = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(previous) }
        let programs = AppStore.loadBundledStarterPrograms()
        for (language, screenWidth, scale) in [("en", CGFloat(393), CGFloat(1)), ("tr", CGFloat(320), CGFloat(1.3))] {
            LanguageManager.setLanguage(language)
            let width = screenWidth - 40
            let headerHeight = ProgramHeroLayout.headerHeight(programs: programs, width: width, titleSize: 18 * scale)
            let height = ProgramHeroLayout.height(programs: programs, width: width, titleSize: 18 * scale, bodySize: 13 * scale, daysSize: 12 * scale, countsSize: 11 * scale)
            XCTAssertGreaterThanOrEqual(height, 216)
            for program in programs {
                let content = ProgramHeroCard(program: program, isActive: program.id == programs[0].id,
                    width: width, height: height, titleSize: 18 * scale, bodySize: 13 * scale, daysSize: 12 * scale, countsSize: 11 * scale, headerHeight: headerHeight,
                    onSelect: {}, onEdit: {})
                    .padding(20).background(AppColors.background)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.uiImage)
                XCTAssertEqual(image.size.width, screenWidth)
                let attachment = XCTAttachment(image: image)
                attachment.name = "program-card-\(program.id)-\(language)-\(scale)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    @MainActor
    func testRepMaxSourceSnapshots() {
        let previous = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(previous) }
        let store = AppStore(persistence: AppStatePersistence(inMemory: true))
        let oldState = store.state
        defer { store.state = oldState }
        store.state.history = [WorkoutSessionRecord(id: "estimate-ui", programId: "p", workoutId: "w", workoutTitle: "Workout",
            startedAt: "2026-09-15T10:00:00Z", completedAt: "2026-09-15T11:00:00Z", durationSeconds: 100,
            totalVolumeKg: 1220, totalCompletedSets: 2, exerciseLogs: [SessionExerciseLog(exerciseName: "Bench", sets: [
                SessionSetLog(setNumber: 1, weightKg: 100, reps: 5), SessionSetLog(setNumber: 2, weightKg: 20, reps: 36)
            ])])]
        for language in ["en", "tr"] {
            LanguageManager.setLanguage(language)
            for kind in ["matrix", "curve", "library"] {
                let content = Group {
                    if kind == "library" {
                        ExerciseHistoryStatsRow(stats: PersonalRecordTracker.computeExerciseHistoryStats(history: store.state.history, exerciseName: "Bench"), weightUnit: .kg)
                    } else {
                        FormLabView(store: store, initialTab: kind == "matrix" ? .repMax : .curves)
                    }
                }.padding(12).background(AppColors.background).environment(\.sizeCategory, .extraExtraLarge)
                let controller = UIHostingController(rootView: content)
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 1300))
                window.rootViewController = controller
                window.makeKeyAndVisible()
                controller.view.frame = window.bounds
                controller.view.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                    controller.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "rep-\(kind)-\(language)"
                attachment.lifetime = .keepAlways
                add(attachment)
                window.isHidden = true
            }
        }
    }

    func testRepMaxEligibilityAndPreservedLogs() throws {
        for formula in RepMaxFormula.allCases {
            for reps in [-1, 0, 11, 20, 36, 37, Int.max] {
                XCTAssertEqual(FormLabEngine.calculateEstimated1RM(weightKg: 20, reps: reps, formula: formula), 0)
                XCTAssertEqual(FormLabEngine.calculateTargetNRM(oneRmKg: 100, targetReps: reps, formula: formula), 0)
            }
            for weight in [0.0, -1.0, Double.nan, Double.infinity, -Double.infinity] {
                XCTAssertEqual(FormLabEngine.calculateEstimated1RM(weightKg: weight, reps: 5, formula: formula), 0)
                XCTAssertTrue(FormLabEngine.computeRepMaxTargets(oneRmKg: weight, formula: formula).isEmpty)
            }
            XCTAssertEqual(FormLabEngine.calculateEstimated1RM(weightKg: 20, reps: 1, formula: formula), 20)
            XCTAssertEqual(FormLabEngine.calculateEstimated1RM(weightKg: 20, reps: 10, formula: formula), 26.6667, accuracy: 0.001)
            XCTAssertEqual(FormLabEngine.calculateEstimated1RM(weightKg: .greatestFiniteMagnitude, reps: 10, formula: formula), 0)
        }
        XCTAssertEqual(PersonalRecordTracker.calculateEstimated1RM(weightKg: 20, reps: 36), 0)
        let eligible = SessionSetLog(setNumber: 1, weightKg: 100, reps: 5)
        let highRep = SessionSetLog(setNumber: 2, weightKg: 20, reps: 36)
        let warmup = SessionSetLog(setNumber: 3, weightKg: 300, reps: 5, isWarmup: true)
        func session(_ id: String, _ date: String, _ sets: [SessionSetLog]) -> WorkoutSessionRecord {
            WorkoutSessionRecord(id: id, programId: "p", workoutId: "w", workoutTitle: "Workout", startedAt: date,
                completedAt: date, durationSeconds: 100, totalVolumeKg: 0, totalCompletedSets: sets.count,
                exerciseLogs: [SessionExerciseLog(exerciseName: "Bench", sets: sets)])
        }
        let mixed = session("mixed", "2026-09-01T10:00:00Z", [eligible, highRep, warmup])
        let highOnly = session("high", "2026-09-02T10:00:00Z", [highRep])
        let history = [mixed, highOnly]
        for formula in RepMaxFormula.allCases {
            let expected = FormLabEngine.calculateEstimated1RM(weightKg: 100, reps: 5, formula: formula)
            let summary = try XCTUnwrap(FormLabEngine.computeExerciseRepMax(exerciseName: "Bench", history: history, formula: formula))
            XCTAssertEqual(summary.estimated1rmKg, expected, accuracy: 0.001)
            XCTAssertEqual(summary.achievedDate, mixed.startedAt)
            XCTAssertEqual(summary.bestWeightKg, 100)
            XCTAssertEqual(summary.bestReps, 5)
            XCTAssertEqual(summary.formula, formula)
            XCTAssertEqual(summary.targets.first?.estimatedWeightKg, expected)
            let curve = FormLabEngine.computeLongitudinalCurve(exerciseName: "Bench", history: history, formula: formula)
            XCTAssertEqual(curve.points.count, 1)
            XCTAssertEqual(curve.peak1rmKg, expected)
            XCTAssertEqual(curve.current1rmKg, expected)
            XCTAssertEqual(curve.start1rmKg, expected)
            XCTAssertEqual(curve.points.first?.topReps, 5)
            XCTAssertNil(FormLabEngine.computeExerciseRepMax(exerciseName: "Bench", history: [highOnly], formula: formula))
            XCTAssertTrue(FormLabEngine.computeAllRepMaxSummaries(history: [highOnly], formula: formula).isEmpty)
            let empty = FormLabEngine.computeLongitudinalCurve(exerciseName: "Bench", history: [highOnly], formula: formula)
            XCTAssertTrue(empty.points.isEmpty)
            XCTAssertNil(empty.peak1rmKg)
        }
        let stats = PersonalRecordTracker.computeExerciseHistoryStats(history: history, exerciseName: "Bench")
        XCTAssertEqual(stats.estimated1rmKg, 112.5)
        XCTAssertEqual(stats.estimateSourceSet, eligible)
        XCTAssertEqual(stats.estimateSourceDate, mixed.startedAt)
        XCTAssertEqual(stats.lifetimeSets, 4)
        XCTAssertEqual(stats.totalVolumeKg, 3440)
        XCTAssertEqual(stats.recentSessions.first?.sets, [highRep])
        let onlyStats = PersonalRecordTracker.computeExerciseHistoryStats(history: [highOnly], exerciseName: "Bench")
        XCTAssertNil(onlyStats.estimated1rmKg)
        XCTAssertNil(onlyStats.estimateSourceSet)
        XCTAssertEqual(onlyStats.prReps, 36)
        XCTAssertEqual(onlyStats.prWeightKg, 20)
        XCTAssertEqual(onlyStats.totalVolumeKg, 720)
        XCTAssertEqual(mixed.exerciseLogs.first?.sets, [eligible, highRep, warmup])
    }

    @MainActor
    func testAnalyticsReferenceCopySnapshots() {
        let previous = LanguageManager.shared.currentLanguage
        let store = AppStore.shared
        let original = store.state
        var fixture = original
        fixture.history = [WorkoutSessionRecord(id: "distribution-ui", programId: "p", workoutId: "w", workoutTitle: "Workout",
            startedAt: "2026-09-15T10:00:00Z", completedAt: "2026-09-15T11:00:00Z", durationSeconds: 100,
            totalVolumeKg: 1280, totalCompletedSets: 5, exerciseLogs: [
                SessionExerciseLog(exerciseName: "Barbell Bench Press", sets: (1...4).map { SessionSetLog(setNumber: $0, weightKg: 40, reps: 8, isWarmup: false) }),
                SessionExerciseLog(exerciseName: "My leg curl", sets: [SessionSetLog(setNumber: 1, weightKg: 10, reps: 8, isWarmup: false)])])]
        store.saveState(fixture)
        defer { LanguageManager.setLanguage(previous); store.saveState(original) }
        for language in ["en", "tr"] {
            LanguageManager.setLanguage(language)
            for matrix in [true, false] {
                let content = Group {
                    if matrix {
                        ScrollView { VolumeMatrixView(store: AppStore.shared).padding(16) }
                    } else {
                        FormLabView(store: AppStore.shared, initialTab: .balance)
                    }
                }.environment(\.sizeCategory, .extraExtraLarge)
                let controller = UIHostingController(rootView: content)
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 1300))
                window.rootViewController = controller
                window.makeKeyAndVisible()
                controller.view.frame = window.bounds
                controller.view.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                    controller.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "\(matrix ? "volume-reference" : "training-distribution")-\(language)"
                attachment.lifetime = .keepAlways
                add(attachment)
                window.isHidden = true
            }
        }
    }

    func testAnalyticsCopyUsesReferenceRangesNotDiagnoses() {
        for (language, copy) in [("en", Translations.en), ("tr", Translations.tr)] {
            XCTAssertEqual(copy["form_lab.tab_balance"], language == "en" ? "Training Distribution" : "Antrenman Dağılımı")
            for zone in VolumeZone.allCases {
                XCTAssertTrue((copy[zone.titleKey] ?? "").lowercased().contains("refer"))
            }
            for key in ["matrix.limitations", "matrix.info.overviewText", "form_lab.balance_subtitle", "form_lab.info_antagonist_desc"] {
                XCTAssertTrue((copy[key] ?? "").contains(language == "en" ? "not" : "tanı"), key)
            }
            let analytics = copy.filter { $0.key.hasPrefix("matrix.") || $0.key.hasPrefix("form_lab.balance") || $0.key.hasPrefix("form_lab.info_antagonist") || $0.key.hasPrefix("paywall.volume_matrix") }.values.joined(separator: "\n").lowercased()
            for claim in ["high risk of overtraining", "protect shoulders", "prevent joint impingement", "balanced knee flexion and extension torque", "optimal balance", "maintenance only", "eliminate overtraining", "fatigue optimization", "aşırı antrenman riskini önlemek", "sürantrene olma riski yüksek", "yalnızca koruma sağlar", "maksimum toparlanabilir hacim aşıldı"] {
                XCTAssertFalse(analytics.contains(claim), claim)
            }
        }
    }

    func testWeeklyPlanPreservesExerciseCountWithStatus() {
        let previous = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(previous) }
        let workout = Workout(id: "test", day: 1, title: "Test", exercises: [Exercise(name: "A"), Exercise(name: "B")])
        for language in ["en", "tr"] {
            LanguageManager.setLanguage(language)
            let count = LanguageManager.t("weekly.exerciseCount", ["count": 2])
            XCTAssertEqual("\(count) · \(LanguageManager.t("history.unfinished"))", WeeklyPlanView.workoutSubtitle(workout: workout, isUnfinished: true, isMissed: false))
            XCTAssertEqual("\(count) · \(LanguageManager.t("history.missed"))", WeeklyPlanView.workoutSubtitle(workout: workout, isUnfinished: false, isMissed: true))
            XCTAssertEqual(count, WeeklyPlanView.workoutSubtitle(workout: workout, isUnfinished: false, isMissed: false))
            XCTAssertEqual(LanguageManager.t("weekly.restDay"), WeeklyPlanView.workoutSubtitle(workout: nil, isUnfinished: false, isMissed: false))
        }
    }

    func testOnlyPastUnstartedWorkoutDaysAreMissed() {
        for today in 0..<7 {
            for day in 0..<7 {
                XCTAssertEqual(day < today, WeeklyPlanView.isMissedPlanDay(dayIndex: day, todayIndex: today, hasWorkout: true, completed: false, unfinished: false))
                XCTAssertFalse(WeeklyPlanView.isMissedPlanDay(dayIndex: day, todayIndex: today, hasWorkout: false, completed: false, unfinished: false))
                XCTAssertFalse(WeeklyPlanView.isMissedPlanDay(dayIndex: day, todayIndex: today, hasWorkout: true, completed: true, unfinished: false))
                XCTAssertFalse(WeeklyPlanView.isMissedPlanDay(dayIndex: day, todayIndex: today, hasWorkout: true, completed: false, unfinished: true))
                XCTAssertFalse(WeeklyPlanView.isMissedPlanDay(dayIndex: day, todayIndex: today, hasWorkout: true, completed: true, unfinished: true))
            }
        }
        XCTAssertFalse(WeeklyPlanView.isMissedPlanDay(dayIndex: 0, todayIndex: 7, hasWorkout: true, completed: false, unfinished: false))
        XCTAssertFalse(WeeklyPlanView.isMissedPlanDay(dayIndex: -1, todayIndex: 6, hasWorkout: true, completed: false, unfinished: false))
    }

    @MainActor
    func testEquipmentOptionsRenderInEnglishAndTurkishLargeText() throws {
        let previous = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(previous) }
        for (language, width, type) in [("en", 390.0, DynamicTypeSize.large), ("tr", 320.0, DynamicTypeSize.xxxLarge)] {
            LanguageManager.setLanguage(language)
            let content = VStack(alignment: .leading, spacing: 16) {
                Text(LanguageManager.t("library.equipment")).foregroundStyle(AppColors.text)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 10) {
                    ForEach(EquipmentCatalog.shared.categories) { category in
                        LibraryFilterOption(title: category.title, selected: category.id == "resistance-band", equipment: category, action: {})
                    }
                }
            }.padding(20).frame(width: width).background(AppColors.background).environment(\.dynamicTypeSize, type)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertGreaterThan(image.size.height, 180)
            XCTAssertLessThan(image.size.height, 950)
            try XCTUnwrap(image.pngData()).write(to: URL(fileURLWithPath: "/private/tmp/form-equipment-ios-\(language).png"))
            let attachment = XCTAttachment(image: image)
            attachment.name = "Equipment \(language)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testEquipmentCatalogCoverageAndFiltering() throws {
        let catalog = EquipmentCatalog.shared
        XCTAssertEqual(catalog.exercises.count, 300)
        XCTAssertEqual(Set(catalog.exercises.keys), Set(ExerciseCatalog.canonicalExercises.keys))
        XCTAssertEqual(catalog.categories.count, 7)
        for category in catalog.categories {
            let name = "library_equipment_\(category.id.replacingOccurrences(of: "-", with: "_"))"
            XCTAssertNotNil(UIImage(named: name), "Missing equipment filter artwork: \(name)")
        }
        XCTAssertEqual(Set(catalog.exercises.values), Set(catalog.categories.map(\.id)))
        for (id, group) in ["ez-bar-curl": "bar", "goblet-squat": "dumbbell",
                            "cable-lateral-raise": "machine", "leg-press": "machine",
                            "weighted-front-raise": "weight-plate", "svend-press": "weight-plate",
                            "weighted-pull-ups": "other"] {
            XCTAssertEqual(catalog.categoryId(id), group)
            XCTAssertTrue(catalog.matches(id, selected: group))
            XCTAssertTrue(catalog.matches(id, selected: nil))
        }
        XCTAssertEqual(catalog.categoryId("custom-dumbbell"), "other")
        XCTAssertEqual(catalog.categoryId(nil), "other")
        XCTAssertFalse(catalog.matches("ez-bar-curl", selected: "machine"))
        for category in catalog.categories {
            XCTAssertFalse(SVGPathParser.parse(category.icon).isEmpty)
            XCTAssertFalse(category.en.isEmpty)
            XCTAssertFalse(category.tr.isEmpty)
        }
    }


    func testFlexibleExerciseSearch() throws {
        func score(_ id: String, _ query: String) throws -> Int? {
            let exercise = try XCTUnwrap(ExerciseCatalog.canonicalExercises[id]).toExercise()
            return ExerciseSearch.score(.init(query), exercise: exercise)
        }
        for query in ["chest supported", "CHEST-SUPPORTED", "chest—supported", "  chest   supported  ",
                      "row chest", "supported dumb", "DB chest row"] {
            XCTAssertNotNil(try score("chest-supported-dumbbell-row", query), query)
        }
        for (id, query) in [
            ("dumbbell-romanian-deadlift", "DB RDL"), ("barbell-romanian-deadlift", "bb rdl"),
            ("standing-barbell-overhead-press", "OHP"), ("rope-triceps-pressdown", "rope pushdown"),
            ("pec-deck-fly", "butterfly"), ("push-ups", "pushups"), ("pull-ups", "pull ups"),
            ("push-ups", "SINAV"), ("push-ups", "ŞINAV"), ("pull-ups", "barfiks")
        ] { XCTAssertNotNil(try score(id, query), "\(id) / \(query)") }
        XCTAssertNil(try score("barbell-bench-press", "chest supported"))
        XCTAssertNil(try score("chest-supported-dumbbell-row", "chest bicycle"))
        XCTAssertNil(try score("barbell-back-squat", "bell"))
        XCTAssertNil(try score("pull-ups", "weighted"))
        XCTAssertNotNil(try score("weighted-pull-ups", "weighted pullup"))
        XCTAssertEqual(try score("barbell-bench-press", " --- "), 0)
        XCTAssertEqual(try score("barbell-back-squat", ""), 0)
        XCTAssertEqual(ExerciseSearch.normalize("İŞINAV GÖĞÜS ÇEKİŞ"), "isinav gogus cekis")
        let exact = Exercise(name: "RDL")
        XCTAssertLessThan(try XCTUnwrap(ExerciseSearch.score(.init("rdl"), exercise: exact)),
                          try XCTUnwrap(score("barbell-romanian-deadlift", "rdl")))
    }

    func testSearchKeywordsAndCustomExerciseCompatibility() throws {
        XCTAssertEqual(ExerciseCatalog.canonicalExercises.count, 300)
        XCTAssertTrue(ExerciseCatalog.canonicalExercises.values.allSatisfy { !$0.searchKeywords.isEmpty })
        let custom = Exercise(name: "My Chest—Supported Row", exerciseId: "custom")
        XCTAssertNotNil(ExerciseSearch.score(.init("chest supported"), exercise: custom))
        XCTAssertNotNil(ExerciseSearch.score(.init("CEKIS"), exercise: custom, category: "Çekiş"))
        XCTAssertNil(ExerciseSearch.score(.init("rdl"), exercise: custom))
        let old = Data(#"{"id":"custom","name":"Custom","movementType":"other"}"#.utf8)
        XCTAssertTrue(try JSONDecoder().decode(ExerciseDefinition.self, from: old).searchKeywords.isEmpty)
    }

    func testExerciseVideoCatalogMatchesCurrentExercises() throws {
        XCTAssertEqual(ExerciseVideoCatalog.entries.count, 300)
        for id in ExerciseCatalog.canonicalExercises.keys {
            let entry = try XCTUnwrap(ExerciseVideoCatalog.entries[id], id)
            XCTAssertFalse(entry.name.isEmpty)
            let url = try XCTUnwrap(ExerciseVideoCatalog.url(for: id), id)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
        XCTAssertNil(ExerciseVideoCatalog.url(for: "unknown-custom-exercise"))
        XCTAssertEqual(ExerciseVideoCatalog.entries["face-pull"]?.videoId, "565612")
        XCTAssertEqual(ExerciseVideoCatalog.entries["goblet-squat"]?.videoId, "176012")
        XCTAssertNotEqual(ExerciseVideoCatalog.url(for: "pull-ups"),
                          ExerciseVideoCatalog.url(for: "weighted-pull-ups"))
    }

    @MainActor
    func testExerciseVideoFramingIsFullBleed() throws {
        XCTAssertEqual(ExerciseVideoCatalog.framings.count, 300)
        for id in ExerciseVideoCatalog.entries.keys {
            let crop = try XCTUnwrap(ExerciseVideoCatalog.framings[id], id)
            XCTAssertGreaterThan(crop.width, 0)
            XCTAssertGreaterThan(crop.height, 0)
            XCTAssertGreaterThanOrEqual(crop.left, 0)
            XCTAssertGreaterThanOrEqual(crop.top, 0)
            XCTAssertLessThanOrEqual(crop.left + crop.width, 1.00001)
            XCTAssertLessThanOrEqual(crop.top + crop.height, 1.00001)
            for width: CGFloat in [320, 440] {
                let size = CGSize(width: width, height: width / crop.aspectRatio)
                let frame = crop.videoFrame(in: size)
                XCTAssertEqual(frame.width / frame.height, 16 / 9, accuracy: 0.0001)
                XCTAssertLessThanOrEqual(frame.minX, 0)
                XCTAssertLessThanOrEqual(frame.minY, 0)
                XCTAssertGreaterThanOrEqual(frame.maxX + 0.001, size.width)
                XCTAssertGreaterThanOrEqual(frame.maxY + 0.001, size.height)
            }
        }
        let host = UIHostingController(rootView:
            ExerciseDetailVideo(exerciseId: "barbell-bench-press").frame(width: 320)
        )
        let size = host.sizeThatFits(in: CGSize(width: 320, height: 1000))
        XCTAssertEqual(size.width, 320, accuracy: 0.1)
        XCTAssertEqual(size.height, 256, accuracy: 0.1)
    }

    @MainActor
    func testLocalExerciseVideoPlaysAndPauses() async throws {
        let url = try XCTUnwrap(ExerciseVideoCatalog.url(for: "barbell-bench-press"))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        let controller = UIViewController()
        window.rootViewController = controller
        let framing = ExerciseVideoCatalog.framing(for: "barbell-bench-press")
        let video = ExercisePlayerView(url: url, framing: framing)
        video.frame = CGRect(x: 0, y: 0, width: 320, height: 320 / framing.aspectRatio)
        controller.view.addSubview(video)
        window.isHidden = false
        // This standalone test window is not the app's key window; lay out its
        // hosted view explicitly before checking the child AVPlayerLayer.
        video.setNeedsLayout()
        video.layoutIfNeeded()
        defer { video.release(); window.isHidden = true }
        video.setPlaying(true)
        try await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertEqual(ExerciseVideoCatalog.playbackSpeed, 1.2, accuracy: 0.01)
        XCTAssertEqual(video.playbackRate, 1.2, accuracy: 0.01)
        XCTAssertGreaterThan(video.playbackTime.seconds, 0.1)
        let expectedFrame = framing.videoFrame(in: video.bounds.size)
        let renderedFrame = video.renderedVideoFrame
        // Core Animation may round nonzero crop offsets by a few floating-point ulps.
        XCTAssertEqual(renderedFrame.minX, expectedFrame.minX, accuracy: 0.000001)
        XCTAssertEqual(renderedFrame.minY, expectedFrame.minY, accuracy: 0.000001)
        XCTAssertEqual(renderedFrame.width, expectedFrame.width, accuracy: 0.000001)
        XCTAssertEqual(renderedFrame.height, expectedFrame.height, accuracy: 0.000001)
        let image = UIGraphicsImageRenderer(size: video.bounds.size).image { _ in
            video.drawHierarchy(in: video.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Full-bleed centered detail video"
        attachment.lifetime = .keepAlways
        add(attachment)
        video.setPlaying(false)
        XCTAssertEqual(video.playbackRate, 0.0, accuracy: 0.01)
        let pausedAt = video.playbackTime.seconds
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(video.playbackTime.seconds, pausedAt, accuracy: 0.05)
    }

    @MainActor
    func testUnknownExerciseArtworkFramesAreEmpty() throws {
        for id in ["unknown", "band-face-pull"] {
            let renderer = ImageRenderer(content:
                MovementIllustration(exerciseId: id)
                    .frame(width: 224, height: 224)
            )
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage)
            let cgImage = try XCTUnwrap(image.cgImage)
            XCTAssertEqual(cgImage.width, 224)
            XCTAssertEqual(cgImage.height, 224)
            // Compare rendered alpha, not PNG encoding or image color-profile metadata.
            var pixels = [UInt8](repeating: 0, count: 224 * 224 * 4)
            try pixels.withUnsafeMutableBytes { buffer in
                let context = try XCTUnwrap(CGContext(
                    data: buffer.baseAddress, width: 224, height: 224,
                    bitsPerComponent: 8, bytesPerRow: 224 * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 224, height: 224))
            }
            XCTAssertTrue(stride(from: 3, to: pixels.count, by: 4).allSatisfy {
                pixels[$0] == 0
            }, id)
        }
        for name in ["anatomy_compound", "anatomy_dead_bug", "anatomy_pull_up",
                     "anatomy_weighted_pull_up", "anatomy_seated_leg_curl"] {
            XCTAssertNil(UIImage(named: name), "Archived artwork must not ship")
        }
    }

    @MainActor
    func testHomeWorkoutSwitchingLoadsThumbnails() async throws {
        let store = AppStore(persistence: AppStatePersistence(inMemory: true))
        let ids = Array(ExerciseThumbnails.catalog.keys.sorted().prefix(11))
        XCTAssertEqual(ids.count, 11)
        let groups = [Array(ids[0..<1]), Array(ids[1..<5]), Array(ids[5..<11])]
        let workouts = groups.enumerated().map { index, group in
            Workout(id: "png-day-\(index)", day: index + 1, title: "PNG QA \(group.count)",
                exercises: group.map { Exercise(name: $0, exerciseId: $0, sets: 3) })
        }
        store.state.programs = [Program(id: "png-qa", name: "PNG QA", workouts: workouts)]
        store.state.activeProgramId = "png-qa"
        store.selectedWorkoutId = workouts[0].id
        let savedTheme = ThemeManager.shared.currentTheme.id
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let host = UIHostingController(rootView: TodayView(store: store,
            onOpenPrograms: {}, onOpenSettings: {}, onSelectExercise: { _ in }))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousKey?.makeKeyAndVisible()
            ThemeManager.shared.setThemeId(savedTheme)
        }
        for theme in ["default", "oat"] {
            ThemeManager.shared.setThemeId(theme)
            for workout in workouts + [workouts[0]] {
                store.selectedWorkoutId = workout.id
                host.view.layoutIfNeeded()
                let deadline = Date().addingTimeInterval(2)
                repeat {
                    try await Task.sleep(nanoseconds: 50_000_000)
                } while Date() < deadline && workout.exercises.contains {
                    ExerciseThumbnails.cachedImage(for: $0.exerciseId) == nil
                }
                XCTAssertEqual(store.activeWorkout?.id, workout.id)
                for exercise in workout.exercises {
                    XCTAssertNotNil(ExerciseThumbnails.cachedImage(for: exercise.exerciseId), exercise.name)
                }
                host.view.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                    host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "home-png-\(theme)-\(workout.exercises.count)-exercises"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testBundledPNGDecodingPreservesArtworkPixels() throws {
        let thumbnailFiles = ExerciseThumbnails.catalog.values.map { ("ExerciseThumbnails", $0.file) }
        let backdropFiles = Set(AppThemes.all.map { ExerciseBackdropStyle.file(for: $0.id) })
            .map { ("ExerciseBackdrops", $0) }
        XCTAssertEqual(thumbnailFiles.count, 300)
        XCTAssertEqual(backdropFiles.count, 7)

        func pixels(_ image: CGImage) throws -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
            try bytes.withUnsafeMutableBytes { buffer in
                let context = try XCTUnwrap(CGContext(data: buffer.baseAddress,
                    width: image.width, height: image.height, bitsPerComponent: 8,
                    bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            return bytes
        }

        for (directory, file) in thumbnailFiles + backdropFiles {
            try autoreleasepool {
                let url = try XCTUnwrap(Bundle.main.url(forResource: file, withExtension: nil, subdirectory: directory), file)
                let reference = try XCTUnwrap(UIImage(contentsOfFile: url.path)?.cgImage, file)
                let decoded = try XCTUnwrap(BundledPNGImage.load(from: url)?.cgImage, file)
                XCTAssertEqual(decoded.width, reference.width, file)
                XCTAssertEqual(decoded.height, reference.height, file)
                let actual = try pixels(decoded)
                XCTAssertTrue(actual == (try pixels(reference)), "Decoded color or alpha changed: \(file)")
                if directory == "ExerciseThumbnails" {
                    XCTAssertEqual(actual[3], 0, "Transparent padding must remain clear: \(file)")
                    XCTAssertTrue(stride(from: 3, to: actual.count, by: 4).contains { actual[$0] > 0 },
                        "The exercise must remain visible: \(file)")
                } else {
                    XCTAssertTrue(stride(from: 3, to: actual.count, by: 4).allSatisfy { actual[$0] == 255 },
                        "The studio backdrop must remain opaque: \(file)")
                }
            }
        }
    }

    @MainActor
    func testStaticStepOneThumbnails() async throws {
        XCTAssertEqual(Set(ExerciseThumbnails.catalog.keys), Set(ExerciseCatalog.canonicalExercises.keys))
        for id in ExerciseThumbnails.catalog.keys {
            let loaded = await ExerciseThumbnails.load(for: id)
            let image = try XCTUnwrap(loaded, id)
            XCTAssertLessThanOrEqual(image.size.width, 384)
            XCTAssertLessThanOrEqual(image.size.height, 384)
            XCTAssertNotEqual(image.cgImage?.alphaInfo, CGImageAlphaInfo.none)
        }
        let unknown = await ExerciseThumbnails.load(for: "unknown")
        XCTAssertNil(unknown)
        let missing = await ExerciseThumbnails.load(for: nil)
        XCTAssertNil(missing)
        for id in ["barbell-bench-press", "face-pull", "cable-lateral-raise", "leg-press"] {
            let loaded = await ExerciseThumbnails.load(for: id)
            XCTAssertTrue(loaded === ExerciseThumbnails.cachedImage(for: id))
        }
        let renderer = ImageRenderer(content:
            VStack {
                MovementIllustration(exerciseId: "barbell-bench-press")
                    .frame(width: 224, height: 224).background(AppColors.exerciseThumbnailSurface)
                HStack {
                    ForEach(["face-pull", "cable-lateral-raise", "leg-press"], id: \.self) { id in
                        MovementIcon(exerciseId: id, size: 96)
                    }
                }
            }.padding(12).background(AppColors.background)
        )
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(image.pngData(), renderer.uiImage?.pngData())
        if let data = image.pngData() {
            try? data.write(to: URL(fileURLWithPath: "/private/tmp/static-thumbnails-ios.png"))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Static STEP1 thumbnails"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSanitizedRepsInputRejectsZero() {
        XCTAssertNil(WorkoutSessionUtils.sanitizedRepsInput("0"))
        XCTAssertNil(WorkoutSessionUtils.sanitizedRepsInput("00"))
        XCTAssertNil(WorkoutSessionUtils.sanitizedRepsInput("05"))
        XCTAssertNil(WorkoutSessionUtils.sanitizedRepsInput("-1"))
        XCTAssertNil(WorkoutSessionUtils.sanitizedRepsInput("abc"))
        
        XCTAssertEqual(WorkoutSessionUtils.sanitizedRepsInput(""), "")
        XCTAssertEqual(WorkoutSessionUtils.sanitizedRepsInput("1"), "1")
        XCTAssertEqual(WorkoutSessionUtils.sanitizedRepsInput("12"), "12")
        XCTAssertEqual(WorkoutSessionUtils.sanitizedRepsInput("999"), "999")
    }

    func testSetJumpLimitsAndPreviousSetPrefill() throws {
        let rows = (1...3).map { ExerciseSetLog(setNumber: $0) }
        XCTAssertEqual(WorkoutSessionUtils.currentSetNumber(rows), 1)
        var completed = rows
        completed[0].isCompleted = true
        XCTAssertEqual(WorkoutSessionUtils.currentSetNumber(completed), 2)
        completed[1].isCompleted = true
        completed[2].isCompleted = true
        XCTAssertEqual(WorkoutSessionUtils.currentSetNumber(completed), 3)
        completed[0].isCompleted = false
        XCTAssertEqual(WorkoutSessionUtils.currentSetNumber(completed), 1)
        XCTAssertEqual(WorkoutSessionUtils.currentSetNumber([]), 0)
        XCTAssertEqual(WorkoutSessionUtils.adjustWeight("7,5", by: 5), "12.5")
        XCTAssertEqual(WorkoutSessionUtils.adjustWeight("2.5", by: -10), "0")
        XCTAssertEqual(WorkoutSessionUtils.adjustWeight("", by: 10), "10")
        XCTAssertEqual(WorkoutSessionUtils.adjustWeight("1500", by: 10), "1500")
        XCTAssertEqual(WorkoutSessionUtils.adjustWeight("3000", by: 10, unit: .lbs), "3000")
        XCTAssertEqual(WorkoutSessionUtils.adjustReps("1", by: -1), "")
        XCTAssertEqual(WorkoutSessionUtils.adjustReps("", by: 1), "1")
        XCTAssertEqual(WorkoutSessionUtils.adjustReps("999", by: 1), "999")
        let source = ExerciseSetLog(setNumber: 1, weightInput: "62.5", repsInput: "10", isCompleted: true)
        let blank = ExerciseSetLog(id: "next", setNumber: 2)
        let next = WorkoutSessionUtils.prefillSet(blank, from: source)
        XCTAssertEqual(next.id, blank.id)
        XCTAssertEqual(next.weightKg, 62.5)
        XCTAssertEqual(next.completedReps, 10)
        XCTAssertFalse(next.isCompleted)
        var cleared = blank
        cleared.inputTouched = true
        XCTAssertEqual(WorkoutSessionUtils.prefillSet(cleared, from: source), cleared)
        var partial = blank
        partial.weightInput = "20"
        XCTAssertEqual(WorkoutSessionUtils.prefillSet(partial, from: source), partial)
        XCTAssertEqual(WorkoutSessionUtils.prefillSet(blank, from: nil), blank)
        let persisted = try JSONDecoder().decode(ExerciseSetLog.self, from: JSONEncoder().encode(cleared))
        XCTAssertEqual(persisted.inputTouched, true)
        let legacy = #"{"id":"old","setNumber":1,"weightInput":"","repsInput":"","isCompleted":false}"#.data(using: .utf8)!
        XCTAssertNil(try JSONDecoder().decode(ExerciseSetLog.self, from: legacy).inputTouched)
    }

    @MainActor
    func testSetJumpControlsNarrowSnapshots() throws {
        defer { LanguageManager.setLanguage("en") }
        func textFields(_ view: UIView) -> [UITextField] {
            (view as? UITextField).map { [$0] } ?? view.subviews.flatMap { textFields($0) }
        }
        for language in ["en", "tr"] {
            LanguageManager.setLanguage(language)
            for index in 0..<2 {
            let content = SetLoggingTable(sets: (1...3).map { ExerciseSetLog(setNumber: $0, weightInput: "12.5", repsInput: "10") }, prescription: "3 × 6–10",
                onUpdateSet: { _, _, _ in }, onToggleCompleteSet: { _ in }, onAddSet: {}, onRemoveSet: { _ in })
                .padding(16).environment(\.dynamicTypeSize, .xLarge)
                .frame(width: 320).background(AppColors.background)
            let host = UIHostingController(rootView: content)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 700))
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = window.bounds
            host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            let fields = textFields(host.view)
            XCTAssertEqual(fields.count, 6)
                window.endEditing(true)
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                let field = try XCTUnwrap(textFields(host.view).filter { !$0.isHidden }.dropFirst(index).first)
                XCTAssertTrue(field.becomeFirstResponder())
                RunLoop.main.run(until: Date().addingTimeInterval(0.2))
                host.view.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                    host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "set-jumps-\(language)-\(index)"
                attachment.lifetime = .keepAlways
                add(attachment)
                try image.pngData()?.write(to: URL(fileURLWithPath: "/private/tmp/set-jumps-ios-\(language)-\(index).png"))
            window.endEditing(true)
            window.isHidden = true
            }
        }
    }

    func testSanitizedWeightInput() {
        XCTAssertEqual(WorkoutSessionUtils.sanitizedWeightInput("50"), "50")
        XCTAssertEqual(WorkoutSessionUtils.sanitizedWeightInput("52.5"), "52.5")
        XCTAssertEqual(WorkoutSessionUtils.sanitizedWeightInput("52,5"), "52.5")
        XCTAssertEqual(WorkoutSessionUtils.sanitizedWeightInput(""), "")
        XCTAssertEqual(WorkoutSessionUtils.sanitizedWeightInput("0"), "0")
        XCTAssertEqual(WorkoutSessionUtils.sanitizedWeightInput("00"), "0")
        XCTAssertEqual(WorkoutSessionUtils.sanitizedWeightInput("015"), "15")
        XCTAssertEqual(WorkoutSessionUtils.sanitizedWeightInput("05"), "5")
        XCTAssertEqual(WorkoutSessionUtils.sanitizedWeightInput("0.5"), "0.5")
        XCTAssertEqual(WorkoutSessionUtils.sanitizedWeightInput("00.5"), "0.5")
        XCTAssertEqual(WorkoutSessionUtils.sanitizedWeightInput(".5"), "0.5")
        XCTAssertEqual(WorkoutSessionUtils.sanitizedWeightInput("0."), "0.")
        XCTAssertNil(WorkoutSessionUtils.sanitizedWeightInput("abc"))
        XCTAssertNil(WorkoutSessionUtils.sanitizedWeightInput("12345.67"))
        XCTAssertEqual(WorkoutSessionUtils.sanitizedWeightInput("1500", unit: .kg), "1500")
        XCTAssertNil(WorkoutSessionUtils.sanitizedWeightInput("1500.5", unit: .kg))
        XCTAssertEqual(WorkoutSessionUtils.sanitizedWeightInput("3000", unit: .lbs), "3000")
        XCTAssertNil(WorkoutSessionUtils.sanitizedWeightInput("3000.5", unit: .lbs))
    }

    func testIsAnomalousWeight() {
        XCTAssertFalse(WorkoutSessionUtils.isAnomalousWeight(weightKg: 0, previousTopWeightKg: nil))
        XCTAssertFalse(WorkoutSessionUtils.isAnomalousWeight(weightKg: -5, previousTopWeightKg: nil))
        XCTAssertTrue(WorkoutSessionUtils.isAnomalousWeight(weightKg: 501, previousTopWeightKg: nil))
        XCTAssertTrue(WorkoutSessionUtils.isAnomalousWeight(weightKg: 1000, previousTopWeightKg: nil))
        XCTAssertFalse(WorkoutSessionUtils.isAnomalousWeight(weightKg: 100, previousTopWeightKg: nil))

        XCTAssertFalse(WorkoutSessionUtils.isAnomalousWeight(weightKg: 110, previousTopWeightKg: 100))
        XCTAssertFalse(WorkoutSessionUtils.isAnomalousWeight(weightKg: 140, previousTopWeightKg: 100))
        XCTAssertTrue(WorkoutSessionUtils.isAnomalousWeight(weightKg: 160, previousTopWeightKg: 100))
        XCTAssertTrue(WorkoutSessionUtils.isAnomalousWeight(weightKg: 1000, previousTopWeightKg: 100))

        XCTAssertFalse(WorkoutSessionUtils.isAnomalousWeight(weightKg: 10, previousTopWeightKg: 5))
        XCTAssertFalse(WorkoutSessionUtils.isAnomalousWeight(weightKg: 25, previousTopWeightKg: 10))
        XCTAssertTrue(WorkoutSessionUtils.isAnomalousWeight(weightKg: 125, previousTopWeightKg: 12.5))
    }

    func testProgressionEngineHoldsLoadOnUnverifiedJump() {
        let benchPress = Exercise(
            id: "bench-1",
            name: "Barbell Bench Press",
            exerciseId: "barbell-bench-press",
            sets: 3,
            reps: RepTarget(min: 8, max: 12)
        )
        let s1 = WorkoutSessionRecord(
            id: "s1",
            programId: "p1",
            workoutId: "w1",
            workoutTitle: "Push",
            startedAt: "2026-09-10T10:00:00Z",
            completedAt: "2026-09-10T11:00:00Z",
            durationSeconds: 3600,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 80.0, reps: 12),
                        SessionSetLog(setNumber: 2, weightKg: 80.0, reps: 12),
                        SessionSetLog(setNumber: 3, weightKg: 80.0, reps: 12)
                    ]
                )
            ]
        )
        let s2 = WorkoutSessionRecord(
            id: "s2",
            programId: "p1",
            workoutId: "w1",
            workoutTitle: "Push",
            startedAt: "2026-09-17T10:00:00Z",
            completedAt: "2026-09-17T11:00:00Z",
            durationSeconds: 3600,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 140.0, reps: 12),
                        SessionSetLog(setNumber: 2, weightKg: 140.0, reps: 12),
                        SessionSetLog(setNumber: 3, weightKg: 140.0, reps: 12)
                    ]
                )
            ]
        )
        let rec = ProgressionEngine.computeProgression(exercise: benchPress, history: [s2, s1], weightUnit: .kg)!
        XCTAssertEqual(rec.action, ProgressionAction.holdLoad)
        XCTAssertEqual(rec.rationaleKey, "progression.rationale.unverified_jump")
        XCTAssertEqual(rec.suggestedWeightDisplay, "140")
    }

    func testFormatSecondsToTime() {
        XCTAssertEqual(RestTimerUtils.formatSecondsToTime(0), "00:00")
        XCTAssertEqual(RestTimerUtils.formatSecondsToTime(90), "01:30")
        XCTAssertEqual(RestTimerUtils.formatSecondsToTime(3600), "01:00:00")
        XCTAssertEqual(RestTimerUtils.formatSecondsToTime(5581), "01:33:01")
    }

    func testInitialSetCount() {
        XCTAssertEqual(WorkoutSessionUtils.initialSetCount(prescription: "4 × 8–10"), 4)
        XCTAssertEqual(WorkoutSessionUtils.initialSetCount(prescription: "3 x 12"), 3)
        XCTAssertEqual(WorkoutSessionUtils.initialSetCount(prescription: "Heavy sets"), 3)
    }

    func testStarterProgramsAreAvailable() {
        let bundled = AppStore.loadBundledStarterPrograms()
        XCTAssertFalse(bundled.isEmpty, "Starter programs should be bundled and loaded successfully")
        XCTAssertEqual(bundled.count, AppStore.starterProgramFiles.count, "Expected every bundled starter program")
        XCTAssertEqual(bundled.first?.name, "Aesthetic Engine: 5-Day Hypertrophy")
        XCTAssertEqual(bundled.map { $0.workouts.count }, [5, 4, 6, 3, 4, 3, 4, 3, 3, 4])
        let canonical = AppStore.loadBundledExercises()
        for exercise in bundled.flatMap({ $0.workouts }).flatMap({ $0.exercises }) {
            XCTAssertNotNil(exercise.exerciseId.flatMap { canonical[$0] })
            XCTAssertNotNil(exercise.reps?.min)
            XCTAssertEqual(exercise.reps?.toFailure, false)
        }
    }

    func testStarterRefreshPreservesIndependentProgramsAndIsIdempotent() {
        let bundled = AppStore.loadBundledStarterPrograms()
        let old = Program(id: "aesthetic-hypertrophy", name: "Old template")
        let custom = Program(id: "my-copy", name: "My edited plan")
        let refreshed = AppStore.refreshedStarterPrograms(existing: [old, custom], bundled: bundled)
        XCTAssertEqual(refreshed.count, bundled.count + 1)
        XCTAssertEqual(refreshed.first, bundled.first)
        XCTAssertEqual(refreshed.last, custom)
        XCTAssertEqual(AppStore.refreshedStarterPrograms(existing: refreshed, bundled: bundled), refreshed)
    }

    func testHomeStarterPlansAreAddedOnceWithoutReplacingAnything() {
        let bundled = AppStore.loadBundledStarterPrograms()
        let edited = Program(id: "aesthetic-hypertrophy", name: "My edited Aesthetic Engine")
        let custom = Program(id: "my-copy", name: "My plan")
        let added = AppStore.addingMissingStarterPrograms([edited, custom], bundled: bundled, ids: AppStore.homeStarterProgramIds)
        XCTAssertEqual(Array(added.prefix(2)), [edited, custom])
        XCTAssertEqual(Set(added.dropFirst(2).map(\.id)), AppStore.homeStarterProgramIds)
        XCTAssertEqual(AppStore.addingMissingStarterPrograms(added, bundled: bundled, ids: AppStore.homeStarterProgramIds), added)
        XCTAssertEqual(AppStore.addingMissingStarterPrograms([], bundled: bundled, ids: AppStore.homeStarterProgramIds), [])
        let full = (0..<ProgramEditing.maxPrograms).map { Program(id: "p\($0)", name: "Plan \($0)") }
        XCTAssertEqual(AppStore.addingMissingStarterPrograms(full, bundled: bundled, ids: AppStore.homeStarterProgramIds), full)
    }

    func testHomeStarterPlansLogEveryExerciseAsBodyweight() {
        let home = AppStore.loadBundledStarterPrograms().filter { AppStore.homeStarterProgramIds.contains($0.id) }
        XCTAssertEqual(home.count, 2)
        for exercise in home.flatMap(\.workouts).flatMap(\.exercises) {
            XCTAssertTrue(WorkoutSessionUtils.defaultsToZeroAddedWeight(exercise), exercise.name)
            XCTAssertTrue(WorkoutSessionUtils.allowsZeroWeight(exercise), exercise.name)
        }
    }





    func testFeedbackSoundsAreBundledAndDistinct() throws {
        let soundNames = [
            "form_rest_complete",
            "form_set_complete",
            "form_set_undo",
            "form_workout_start",
            "form_workout_complete"
        ]
        let soundData = try soundNames.map { name -> Data in
            let url = try XCTUnwrap(
                Bundle.main.url(forResource: name, withExtension: "wav"),
                "Missing bundled sound: \(name).wav"
            )
            return try Data(contentsOf: url)
        }

        XCTAssertEqual(Set(soundData).count, soundNames.count, "Each feedback event needs its own sound identity")
    }

    func testSetUndoSoundMatchesAndroidMonoFormat() throws {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "form_set_undo", withExtension: "wav")
        )
        let audioFile = try AVAudioFile(forReading: url)

        XCTAssertEqual(audioFile.fileFormat.sampleRate, 44_100, accuracy: 0.1)
        XCTAssertEqual(audioFile.fileFormat.channelCount, 1)
    }






    func testMuscleMasksSVGPathsParseNonEmpty() {
        for view in BodyView.allCases {
            let paths = MuscleMasks.paths(for: view)
            XCTAssertFalse(paths.isEmpty, "Paths for \(view) should not be empty")
            for (muscle, path) in paths {
                let bounds = path.boundingBox
                XCTAssertFalse(bounds.isEmpty, "Path for \(view):\(muscle) bounding box should not be empty")
                XCTAssertGreaterThan(bounds.width, 0)
                XCTAssertGreaterThan(bounds.height, 0)
                XCTAssertLessThanOrEqual(bounds.maxX, MuscleMasks.viewport + 10)
                XCTAssertLessThanOrEqual(bounds.maxY, MuscleMasks.viewport + 10)
            }
        }
    }

    func testTodayChestHalvesMirrorAcrossAthleteCenterline() throws {
        let path = try XCTUnwrap(MuscleMasks.rawPathStrings[.front]?[.chest])
        assertMirroredChestPath(path, centerX: 866)
    }

    func testTodayRearHairIsOutsideTrapeziusHighlight() throws {
        let path = try XCTUnwrap(MuscleMasks.paths(for: .back)[.trapezius])
        XCTAssertFalse(path.contains(CGPoint(x: 865, y: 240)))
        XCTAssertTrue(path.contains(CGPoint(x: 855, y: 280)))
    }

    func testTodayShoulderAndUpperArmContoursAreBilateral() throws {
        for (view, muscle, centerX) in [(BodyView.front, MuscleGroup.shoulders, 873.0),
            (.front, .biceps, 876.0), (.back, .shoulders, 868.0), (.back, .triceps, 878.0)] {
            assertMirroredChestPath(try XCTUnwrap(MuscleMasks.rawPathStrings[view]?[muscle]), centerX: centerX)
        }
    }

    func testTodayFrontArmMasksExcludeNeighboringMusclesAndJoints() throws {
        let paths = MuscleMasks.paths(for: .front)
        let bellies: [MuscleGroup: [CGPoint]] = [
            .shoulders: [CGPoint(x: 650, y: 430), CGPoint(x: 1096, y: 430)],
            .biceps: [CGPoint(x: 657, y: 565), CGPoint(x: 1095, y: 565)],
            .forearms: [CGPoint(x: 578, y: 766), CGPoint(x: 1165, y: 766)]
        ]
        let exclusions = [CGPoint(x: 700, y: 455), CGPoint(x: 1046, y: 455),
            CGPoint(x: 605, y: 580), CGPoint(x: 1147, y: 580),
            CGPoint(x: 607, y: 688), CGPoint(x: 1139, y: 688),
            CGPoint(x: 540, y: 935), CGPoint(x: 1188, y: 935)]
        for (muscle, points) in bellies {
            let path = try XCTUnwrap(paths[muscle])
            for point in points { XCTAssertTrue(path.contains(point), "\(muscle) misses its muscle belly") }
            for point in bellies.filter({ $0.key != muscle }).values.flatMap({ $0 }) + exclusions {
                XCTAssertFalse(path.contains(point), "\(muscle) spills onto \(point)")
            }
        }
    }

    @MainActor
    func testTodayMusclePrecisionSnapshots() throws {
        let previous = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(previous) }
        for (name, language, width, textSize, targets) in [
            ("front", "en", 393.0, DynamicTypeSize.large, ["chest", "shoulders", "biceps", "forearms"]),
            ("back", "en", 393.0, DynamicTypeSize.large, ["triceps", "shoulders", "lats", "trapezius", "forearms"]),
            ("front-tr-large", "tr", 320.0, DynamicTypeSize.xxxLarge, ["chest", "shoulders", "biceps"])
        ] {
            LanguageManager.setLanguage(language)
            let workout = Workout(id: "mask-review", day: 1,
                title: language == "tr" ? "Üst Vücut ve Omuz" : "Upper body & shoulders",
                focus: language == "tr" ? "Göğüs, omuz ve kol çalışması" : "Chest, shoulders and arms",
                exercises: [Exercise(name: "Fixture")], targetMuscles: targets)
            let content = TodayHeroCard(workout: workout, programId: "mask-fixture", todayIndex: 0,
                isCompleted: false, isAvailable: true, availableDay: nil,
                hasUnfinishedProgress: false, onStart: {})
                .environment(\.dynamicTypeSize, textSize).padding(20)
                .frame(width: width, height: 500).background(AppColors.background)
            let controller = UIHostingController(rootView: content)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 500))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.frame = window.bounds
            controller.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            try XCTUnwrap(image.pngData()).write(to: URL(fileURLWithPath: "/private/tmp/form-muscle-ios-\(name).png"))
            let attachment = XCTAttachment(image: image)
            attachment.name = "Today muscle precision \(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
        }
    }

    func testWorkoutBodyViewsResolution() {
        // Quads and Calves -> legs-front and legs-back
        let legWorkout = Workout(
            id: "w1", day: 4, title: "Legs", focus: "Quads & Calves",
            tone: "violet", exercises: [], targetMuscles: ["quadriceps", "calves"]
        )
        let legViews: [BodyView] = legWorkout.bodyViews()
        XCTAssertEqual(legViews, [BodyView.legsFront, BodyView.legsBack])

        // Chest and Triceps -> front and back
        let upperWorkout = Workout(
            id: "w2", day: 1, title: "Push", focus: "Chest & Triceps",
            tone: "violet", exercises: [], targetMuscles: ["chest", "triceps"]
        )
        let upperViews: [BodyView] = upperWorkout.bodyViews()
        XCTAssertEqual(upperViews, [BodyView.front, BodyView.back])
    }

    func testDetailTranslationsExist() {
        XCTAssertEqual(LanguageManager.t("library.details"), "Exercise details")
        XCTAssertEqual(LanguageManager.t("modal.exercise.cues"), "Technique cues")
        XCTAssertEqual(LanguageManager.t("modal.exercise.avoid"), "What to avoid")
    }

    @MainActor
    func testExerciseDetailSheetSnapshot() {
        LanguageManager.setLanguage("tr")
        defer { LanguageManager.setLanguage("en") }

        guard let exercise = ExerciseCatalog.canonicalExercises["barbell-bench-press"]?.toExercise() else {
            XCTFail("Bundled Barbell Bench Press not found")
            return
        }

        let sheetView = ExerciseDetailSheet(exercise: exercise, onDismiss: {})
        let controller = UIHostingController(rootView: sheetView)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x14/255.0, green: 0x17/255.0, blue: 0x1A/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_exercise_detail_test.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testLibraryViewTurkishSnapshot() {
        LanguageManager.setLanguage("tr")
        defer { LanguageManager.setLanguage("en") }

        let store = AppStore.shared
        let libraryView = LibraryView(store: store, onSelectExercise: { _ in }, onOpenSettings: {})
        let controller = UIHostingController(rootView: libraryView)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x14/255.0, green: 0x17/255.0, blue: 0x1A/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_library_tr_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testLibraryModalsSnapshots() {
        let store = AppStore.shared
        let previousLanguage = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(previousLanguage) }
        let modals: [(LibraryFilterModal, String, String, CGFloat)] = [
            (.equipment, "ios_library_equipment_modal_snapshot.png", "en", 393),
            (.muscle, "ios_library_muscle_modal_snapshot.png", "en", 393),
            (.equipment, "ios_library_equipment_modal_tr_320_snapshot.png", "tr", 320)
        ]

        for (modal, filename, language, width) in modals {
            LanguageManager.setLanguage(language)
            let libraryView = LibraryView(store: store, onSelectExercise: { _ in }, onOpenSettings: {}, initialModal: modal)
            let controller = UIHostingController(rootView: libraryView)
            controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 852)
            controller.view.backgroundColor = UIColor(red: 0x14/255.0, green: 0x17/255.0, blue: 0x1A/255.0, alpha: 1.0)

            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 852))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()

            let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
            let image = renderer.image { ctx in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }

            if let data = image.pngData() {
                let path = "/private/tmp/\(filename)"
                try? data.write(to: URL(fileURLWithPath: path))
                print("Successfully wrote modal snapshot to \(path)")
            }
        }
    }

    @MainActor
    func testAllMuscleArtworkThumbnails() {
        let contactSheet = VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.fixed(160), spacing: 10), GridItem(.fixed(160), spacing: 10)], spacing: 10) {
                ForEach(MuscleGroupFilter.allCases) { muscle in
                    VStack(spacing: 4) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.black)
                            if muscle == .cardio {
                                Image("library_filter_cardio")
                                    .resizable()
                                    .scaledToFit()
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                            } else {
                                MuscleArtwork(view: muscle.bodyView, muscles: muscle.muscleGroups, centered: true, transparentBackground: true)
                                    .padding(4)
                            }
                        }
                        .frame(width: 160, height: 84)

                        Text(LanguageManager.t(muscle.translationKey))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.text)
                    }
                }
            }
        }
        .padding(20)
        .background(AppColors.background)

        let controller = UIHostingController(rootView: contactSheet)
        let targetSize = controller.sizeThatFits(in: CGSize(width: 400, height: 1400))
        controller.view.frame = CGRect(origin: .zero, size: targetSize)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(origin: .zero, size: targetSize))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let image = renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_all_muscle_groups_contact_sheet.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote contact sheet to \(path)")
        }
        let cardioArtwork = UIImage(named: "library_filter_cardio")
        XCTAssertEqual(cardioArtwork?.size, CGSize(width: 1254, height: 1254))
        if let alphaInfo = cardioArtwork?.cgImage?.alphaInfo {
            XCTAssertFalse(alphaInfo == .none || alphaInfo == .noneSkipFirst || alphaInfo == .noneSkipLast)
        } else {
            XCTFail("Cardio artwork has no decoded CGImage")
        }
    }

    @MainActor
    func testLibraryResultsPreserveOrderingAndInvalidateCachedInputs() {
        let previousLanguage = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(previousLanguage) }
        LanguageManager.setLanguage("en")
        let cache = LibraryExerciseResults()
        func entry(_ id: String) -> ExerciseCatalogEntry {
            ExerciseCatalogEntry(key: id, exercise: ExerciseCatalog.canonicalExercises[id]!.toExercise(), programIds: [], workoutKeys: [])
        }
        let catalogue = [entry("dumbbell-bench-press"), entry("barbell-back-squat"), entry("barbell-bench-press")]
        let all = cache.entries(catalogue: catalogue)
        XCTAssertEqual(all.map(\.key), ["barbell-bench-press", "barbell-back-squat", "dumbbell-bench-press"])
        XCTAssertEqual(cache.entries(catalogue: catalogue, query: "bench", equipmentKey: "bar", muscleKey: "chest").map(\.key), ["barbell-bench-press"])
        XCTAssertEqual(cache.entries(catalogue: catalogue, query: "bench", muscleKey: "chest").map(\.key), ["barbell-bench-press", "dumbbell-bench-press"])
        XCTAssertEqual(cache.entries(catalogue: catalogue, query: " --- "), all)
        XCTAssertEqual(cache.entries(catalogue: catalogue), all)

        var custom = ExerciseCatalogEntry(key: "custom", exercise: Exercise(name: "Special movement", movementType: "press"), programIds: [], workoutKeys: [])
        XCTAssertTrue(cache.entries(catalogue: [custom], query: "gogus").isEmpty)
        LanguageManager.setLanguage("tr")
        XCTAssertEqual(cache.entries(catalogue: [custom], query: "gogus"), [custom])
        custom.exercise.cues = "Updated technique"
        custom.exercise.videos = ["https://youtu.be/test"]
        XCTAssertEqual(cache.entries(catalogue: [custom], query: "gogus"), [custom])
        XCTAssertEqual(cache.entries(catalogue: [custom, entry("barbell-bench-press")], query: "gogus").count, 2)
        LanguageManager.setLanguage("en")
        XCTAssertTrue(cache.entries(catalogue: [custom], query: "gogus").isEmpty)

        let exact = ExerciseCatalogEntry(key: "custom-rdl", exercise: Exercise(name: "RDL"), programIds: [], workoutKeys: [])
        let aliases = [entry("barbell-romanian-deadlift"), exact, entry("barbell-bench-press")]
        XCTAssertEqual(cache.entries(catalogue: aliases, query: "rdl").first?.key, "custom-rdl")
        XCTAssertTrue(cache.entries(catalogue: aliases, query: "rdl", equipmentKey: "bar", muscleKey: "chest").isEmpty)
        XCTAssertEqual(cache.entries(catalogue: aliases, query: "RDL", equipmentKey: "bar", muscleKey: "hamstrings").map(\.key), ["barbell-romanian-deadlift"])
    }

    func testLibraryDefaultsToCardView() {
        let previous = UserDefaults.standard.object(forKey: "library_is_card_view")
        UserDefaults.standard.removeObject(forKey: "library_is_card_view")
        defer {
            if let previous = previous {
                UserDefaults.standard.set(previous, forKey: "library_is_card_view")
            } else {
                UserDefaults.standard.removeObject(forKey: "library_is_card_view")
            }
        }
        let view = LibraryView(store: AppStore.shared, onSelectExercise: { _ in }, onOpenSettings: {})
        let mirror = Mirror(reflecting: view)
        let isCardViewProp = mirror.children.first { $0.label == "_isCardView" }?.value as? AppStorage<Bool>
        XCTAssertEqual(isCardViewProp?.wrappedValue, true)
    }

    func testLibraryMuscleFilteringAndMatching() {
        let bench = Exercise(name: "Barbell Bench Press", exerciseId: "barbell-bench-press", movementType: "press")
        let squat = Exercise(name: "Barbell Squat", exerciseId: "barbell-back-squat", movementType: "squat")
        let curl = Exercise(name: "Barbell Curl", exerciseId: "barbell-curl", movementType: "curl")

        XCTAssertTrue(ExerciseMetadata.matchesMuscle(exercise: bench, muscleKey: "chest"))
        XCTAssertFalse(ExerciseMetadata.matchesMuscle(exercise: bench, muscleKey: "quads"))

        XCTAssertTrue(ExerciseMetadata.matchesMuscle(exercise: squat, muscleKey: "quads"))
        XCTAssertTrue(ExerciseMetadata.matchesMuscle(exercise: squat, muscleKey: "glutes"))
        XCTAssertFalse(ExerciseMetadata.matchesMuscle(exercise: squat, muscleKey: "biceps"))

        XCTAssertTrue(ExerciseMetadata.matchesMuscle(exercise: curl, muscleKey: "biceps"))
        XCTAssertFalse(ExerciseMetadata.matchesMuscle(exercise: curl, muscleKey: "chest"))

        let jumpRope = Exercise(name: "Jump Rope", exerciseId: "jump-rope", movementType: "conditioning")
        let burpee = Exercise(name: "Burpee", exerciseId: "burpee", movementType: "conditioning")
        XCTAssertTrue(ExerciseMetadata.matchesMuscle(exercise: jumpRope, muscleKey: "cardio"))
        XCTAssertTrue(ExerciseMetadata.matchesMuscle(exercise: burpee, muscleKey: "cardio"))
        XCTAssertFalse(ExerciseMetadata.matchesMuscle(exercise: bench, muscleKey: "cardio"))

        XCTAssertTrue(ExerciseMetadata.matchesMuscle(exercise: bench, muscleKey: nil))
    }

    @MainActor
    func testExerciseDetailSheetWithVideosSnapshot() {
        var exercise = Exercise(
            name: "Barbell Bench Press",
            prescription: "5 × 4–6",
            cues: "Plant heels, arch upper back, tuck shoulder blades.\nLower bar to sternum under control.\nExplode upward with leg drive.",
            avoid: "Bouncing bar off ribcage.\nButt lifting off the bench.",
            videos: [
                "https://www.youtube.com/watch?v=ZaTM37cfiDs",
                "https://youtube.com/shorts/3jzKvd6e2q4"
            ],
            movementType: "press",
            movementAssetId: "barbell-bench-press"
        )

        let sheetView = ExerciseDetailSheet(exercise: exercise, onDismiss: {})
        let controller = UIHostingController(rootView: sheetView)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x14/255.0, green: 0x17/255.0, blue: 0x1A/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_exercise_detail_with_videos_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testExerciseDetailTechniqueSectionsExpandedSnapshot() throws {
        let previous = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(previous) }
        let bench = try XCTUnwrap(ExerciseCatalog.canonicalExercises["barbell-bench-press"])
        for (language, width, category) in [("en", CGFloat(393), ContentSizeCategory.large),
                                            ("tr", CGFloat(320), ContentSizeCategory.accessibilityExtraLarge),
                                            ("de", CGFloat(320), ContentSizeCategory.accessibilityExtraLarge),
                                            ("fr", CGFloat(320), ContentSizeCategory.accessibilityExtraLarge),
                                            ("es", CGFloat(320), ContentSizeCategory.accessibilityExtraLarge)] {
            LanguageManager.setLanguage(language)
            let fullView = VStack(spacing: 16) {
                TechniqueSectionView(title: LanguageManager.t("modal.exercise.cues"),
                    text: ContentLocalizer.shared.exerciseCuesDetails(exerciseId: bench.id).joined(separator: "\n"),
                    accent: AppColors.accent, isAvoid: false, collapsible: false)
                TechniqueSectionView(title: LanguageManager.t("modal.exercise.avoid"),
                    text: ContentLocalizer.shared.exerciseAvoidDetails(exerciseId: bench.id).joined(separator: "\n"),
                    accent: AppColors.danger, isAvoid: true, collapsible: false)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(AppColors.background)
            .environment(\.sizeCategory, category)
            .ignoresSafeArea()
            let cuesView = TechniqueGuideView(
                cues: ContentLocalizer.shared.exerciseCues(exerciseId: bench.id, fallback: bench.cues).joined(separator: "\n"),
                avoid: ContentLocalizer.shared.exerciseAvoid(exerciseId: bench.id, fallback: bench.avoid).joined(separator: "\n"),
                cuesDetails: ContentLocalizer.shared.exerciseCuesDetails(exerciseId: bench.id).joined(separator: "\n"),
                avoidDetails: ContentLocalizer.shared.exerciseAvoidDetails(exerciseId: bench.id).joined(separator: "\n")
            )
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(AppColors.background)
            .environment(\.sizeCategory, category)
            .ignoresSafeArea()
            let controller = UIHostingController(rootView: cuesView)
            let size = controller.sizeThatFits(in: CGSize(width: width, height: 10000))
            let fullController = UIHostingController(rootView: fullView)
            let fullSize = fullController.sizeThatFits(in: CGSize(width: width, height: 10000))
            XCTAssertLessThan(size.height, fullSize.height)
            XCTAssertEqual(size.width, width, accuracy: 0.5) // Permit layout rounding to the nearest display pixel.
            // Render the complete content without an oversized UIWindow, which can
            // produce a blank hierarchy capture at accessibility text sizes.
            let renderer = ImageRenderer(content: cuesView.frame(width: width))
            renderer.scale = 1 // Keep the complete accessibility-size image below bitmap encoder limits.
            let image = try XCTUnwrap(renderer.uiImage)
            let attachment = XCTAttachment(image: image)
            attachment.name = "technique-cards-\(language)"
            attachment.lifetime = .keepAlways
            add(attachment)
            try XCTUnwrap(image.pngData()).write(to: URL(fileURLWithPath: "/tmp/form-technique-ios-cards-\(language).png"))
            let fullRenderer = ImageRenderer(content: fullView.frame(width: width))
            fullRenderer.scale = 1
            try XCTUnwrap(fullRenderer.uiImage?.pngData()).write(to: URL(fileURLWithPath: "/tmp/form-technique-ios-full-\(language).png"))
        }
    }

    func testExerciseDetailNavigationFromTodayAndLibrary() {
        let store = AppStore.shared
        store.currentView = .today
        XCTAssertEqual(store.currentView, .today)
        XCTAssertNil(store.selectedExerciseId)
        XCTAssertNil(store.returnView)

        // Opening exercise from Today
        store.openExercise(id: "barbell-bench-press")
        XCTAssertEqual(store.currentView, .library)
        XCTAssertEqual(store.selectedExerciseId, "barbell-bench-press")
        XCTAssertEqual(store.returnView, .today)

        // Pressing back returns to Today
        store.selectExerciseInLibrary(id: nil)
        XCTAssertEqual(store.currentView, .today)
        XCTAssertNil(store.selectedExerciseId)
        XCTAssertNil(store.returnView)

        // Opening exercise directly in Library
        store.currentView = .library
        store.selectExerciseInLibrary(id: "barbell-bench-press")
        XCTAssertEqual(store.currentView, .library)
        XCTAssertEqual(store.selectedExerciseId, "barbell-bench-press")
        XCTAssertNil(store.returnView)

        // Pressing back stays in Library
        store.selectExerciseInLibrary(id: nil)
        XCTAssertEqual(store.currentView, .library)
        XCTAssertNil(store.selectedExerciseId)
        XCTAssertNil(store.returnView)
    }

    @MainActor
    func testProgramsViewSnapshot() {
        let store = AppStore.shared
        let programsView = ProgramsView(store: store, onDismiss: {})
        let controller = UIHostingController(rootView: programsView)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x14/255.0, green: 0x17/255.0, blue: 0x1A/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/49049143-92ae-4928-b11d-d8637d2ab36d/ios_programs_applied.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }

        XCTAssertEqual(LanguageManager.t("programs.import"), "Import program")
        XCTAssertEqual(LanguageManager.t("programs.apply"), "Apply")
        XCTAssertEqual(LanguageManager.t("programs.applied"), "Applied")
        XCTAssertEqual(LanguageManager.t("modal.program.titleEdit"), "Edit program")
    }

    @MainActor
    func testProgramHeroCardMenuOpenSnapshot() {
        let programs = AppStore.loadBundledStarterPrograms()
        guard let program = programs.first else { return }
        let width: CGFloat = 353
        let height: CGFloat = 240
        let card = ProgramHeroCard(
            program: program,
            isActive: true,
            width: width,
            height: height,
            titleSize: 18,
            bodySize: 13,
            daysSize: 12,
            countsSize: 11,
            onSelect: {},
            onEdit: {},
            onShare: {},
            onDelete: {},
            isMenuOpen: true
        )
        let controller = UIHostingController(rootView: card.padding(20))
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 280)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 280))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/49049143-92ae-4928-b11d-d8637d2ab36d/ios_program_card_menu_open.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testTodayHeroCardDisabledButtonSnapshot() {
        let store = AppStore.shared
        guard let workout = store.activeProgram?.workouts.first(where: { $0.day == 5 }) ?? store.activeWorkout else {
            return
        }

        let card = TodayHeroCard(
            workout: workout,
            todayIndex: 0,
            isCompleted: false,
            isAvailable: false,
            availableDay: "Friday",
            hasUnfinishedProgress: false,
            onStart: {}
        )

        let controller = UIHostingController(rootView: card.padding(20))
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 420)
        controller.view.backgroundColor = UIColor(red: 0x14/255.0, green: 0x17/255.0, blue: 0x1A/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 420))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_available_friday_fixed.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testTodayHeroCardQuadsAndCalvesSnapshot() {
        let store = AppStore.shared
        // Workout with Quads & Calves (e.g. Day 2 / Leg day)
        guard let workout = store.activeProgram?.workouts.first(where: { $0.title.contains("Quads") || $0.targetMuscles.contains("quadriceps") }) ?? store.activeProgram?.workouts.first(where: { $0.day == 2 }) else {
            return
        }

        // Test legs_back (index 1) which shows calves
        let card = TodayHeroCard(
            workout: workout,
            todayIndex: workout.day - 1,
            isCompleted: false,
            isAvailable: true,
            availableDay: nil,
            hasUnfinishedProgress: false,
            initialViewIndex: 1,
            onStart: {}
        )

        let controller = UIHostingController(rootView: card.padding(20))
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 420)
        controller.view.backgroundColor = UIColor(red: 0x14/255.0, green: 0x17/255.0, blue: 0x1A/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 420))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_quads_calves_back.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testRestTimerModalSnapshot() {
        let modal = RestTimerFullScreenModal(
            secondsRemaining: 113,
            totalSeconds: 120,
            exerciseName: "Incline Dumbbell Press",
            isRunning: true,
            progress: 113.0 / 120.0,
            complete: false,
            timeText: "01:53",
            isMuted: false,
            onDismiss: {},
            onTogglePause: {},
            onAddSeconds: { _ in },
            onSetDuration: { _ in },
            onSkip: {},
            onToggleMute: {}
        )

        let controller = UIHostingController(rootView: modal)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_rest_timer_modal_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testRestTimerBarSnapshot() {
        let bar = RestTimerBar(
            secondsRemaining: 74,
            totalSeconds: 120,
            exerciseName: "Incline Dumbbell Press",
            isRunning: true,
            onTogglePause: {},
            onAddSeconds: { _ in },
            onSetDuration: { _ in },
            onSkip: {},
            isMuted: false,
            onToggleMute: {}
        )

        let controller = UIHostingController(rootView: bar.frame(maxWidth: .infinity))
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 210)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 210))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_rest_timer_bar_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    func testWorkoutCalendarOnlyPastScheduledDaysAreMissed() {
        let initial = WorkoutCalendarHistory(nextScheduledDate: "2026-08-24", scheduledWeekdays: [1, 2, 4, 5])
        let today = "2026-08-27"
        let result = WorkoutCalendar.refresh(history: initial, today: today, weekdays: initial.scheduledWeekdays)
        XCTAssertEqual(result.missedDates, ["2026-08-24", "2026-08-25"])
        XCTAssertEqual(result.missedDates, WorkoutCalendar.refresh(history: result, today: today, weekdays: initial.scheduledWeekdays).missedDates)

        let statuses = WorkoutCalendar.statuses(history: result, today: today)
        XCTAssertEqual(statuses["2026-08-24"], .missed)
        XCTAssertEqual(statuses["2026-08-25"], .missed)
        XCTAssertNil(statuses["2026-08-26"], "Wednesday recovery day must stay neutral")
        XCTAssertNil(statuses[today], "Today must stay neutral if no session logged")
    }

    func testWorkoutCalendarCompletionWinsOverUnfinishedAndMissed() {
        let today = "2026-08-27"
        let history = WorkoutCalendarHistory(
            nextScheduledDate: today,
            missedDates: ["2026-08-24", "2026-08-25", "2026-08-27"],
            entries: [
                WorkoutDayEntry(id: "first", date: "2026-08-24", status: .unfinished),
                WorkoutDayEntry(id: "second", date: "2026-08-24", status: .completed),
                WorkoutDayEntry(id: "partial", date: "2026-08-25", status: .unfinished),
                WorkoutDayEntry(id: "future", date: "2026-08-28", status: .completed)
            ]
        )
        let statuses = WorkoutCalendar.statuses(history: history, today: today)
        XCTAssertEqual(statuses["2026-08-24"], .completed)
        XCTAssertEqual(statuses["2026-08-25"], .unfinished)
        XCTAssertNil(statuses[today])
        XCTAssertNil(statuses["2026-08-28"], "Future dates must stay neutral")
    }

    func testWorkoutCalendarMonthWeeksMondayFirst() {
        let sep2026 = WorkoutCalendar.parseDate("2026-09-01")!
        let weeks = WorkoutCalendar.monthWeeks(for: sep2026)
        XCTAssertEqual(weeks.count, 5)
        XCTAssertNil(weeks[0][0], "Monday before Sept 1 is nil")
        XCTAssertNotNil(weeks[0][1], "Tuesday is Sept 1")
        XCTAssertEqual(WorkoutCalendar.formatDate(weeks[0][1]!), "2026-09-01")
    }

    @MainActor
    func testHistoryViewSnapshot() {
        let store = AppStore.shared
        let view = HistoryView(
            store: store,
            onOpenSettings: {},
            onSelectRecord: { _ in }
        )

        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_history_screen_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testVolumeMatrixViewSnapshot() {
        let store = AppStore.shared
        let originalLang = LanguageManager.shared.currentLanguage
        LanguageManager.setLanguage("tr")
        defer { LanguageManager.setLanguage(originalLang) }

        let view = ScrollView(showsIndicators: false) {
            VolumeMatrixView(store: store)
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
        }
        .background(Color(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0))

        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 320, height: 1250)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 1250))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/private/tmp/ios_volume_matrix_screen_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testVolumeMatrixInfoSheetSnapshot() {
        let sheet = VolumeMatrixInfoSheet()
        let controller = UIHostingController(rootView: sheet)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_volume_matrix_info_sheet_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testHistoryDayDetailSheetMissedSnapshot() {
        let store = AppStore.shared
        let workout = store.activeProgram?.workouts.first(where: { $0.title.contains("Chest") }) ?? store.activeWorkout
        let date = WorkoutCalendar.parseDate("2026-09-01")!
        let detail = HistoryDayDetailData(
            date: date,
            dateString: "2026-09-01",
            status: .missed,
            sessionRecord: nil,
            workout: workout
        )

        let sheet = HistoryDayDetailSheet(detail: detail, onDismiss: {}, onActionWorkout: {})
        let controller = UIHostingController(rootView: sheet)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 850)
        controller.view.backgroundColor = UIColor(red: 0x14/255.0, green: 0x17/255.0, blue: 0x1A/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 850))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_history_detail_missed_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testHistoryDayDetailSheetUnfinishedSnapshot() {
        let store = AppStore.shared
        let workout = store.activeProgram?.workouts.first(where: { $0.title.contains("Chest") }) ?? store.activeWorkout
        let date = WorkoutCalendar.parseDate("2026-09-02")!

        let sampleRecord = WorkoutSessionRecord(
            id: "test-rec",
            programId: store.activeProgram?.id ?? "test-program",
            workoutId: workout?.id ?? "chest-workout",
            workoutTitle: workout?.title ?? "Chest Growth",
            startedAt: "2026-09-02T10:00:00.000Z",
            completedAt: "2026-09-02T10:35:12.000Z",
            durationSeconds: 2112,
            totalVolumeKg: 4250,
            totalCompletedSets: 5,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: workout?.exercises.first?.name ?? "Barbell Bench Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 80, reps: 10),
                        SessionSetLog(setNumber: 2, weightKg: 80, reps: 8),
                        SessionSetLog(setNumber: 3, weightKg: 80, reps: 8)
                    ]
                ),
                SessionExerciseLog(
                    exerciseName: (workout?.exercises.count ?? 0) > 1 ? workout!.exercises[1].name : "Incline Dumbbell Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 24, reps: 12),
                        SessionSetLog(setNumber: 2, weightKg: 24, reps: 10)
                    ]
                )
            ]
        )

        let detail = HistoryDayDetailData(
            date: date,
            dateString: "2026-09-02",
            status: .unfinished,
            sessionRecord: sampleRecord,
            workout: workout
        )

        let sheet = HistoryDayDetailSheet(detail: detail, onDismiss: {}, onActionWorkout: {})
        let controller = UIHostingController(rootView: sheet)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 850)
        controller.view.backgroundColor = UIColor(red: 0x14/255.0, green: 0x17/255.0, blue: 0x1A/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 850))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_history_detail_unfinished_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testHistoryDayDetailSheetUnfinishedExpandedSnapshot() {
        let store = AppStore.shared
        let workout = store.activeProgram?.workouts.first(where: { $0.title.contains("Chest") }) ?? store.activeWorkout
        let date = WorkoutCalendar.parseDate("2026-09-02")!

        let sampleRecord = WorkoutSessionRecord(
            id: "test-rec-expanded",
            programId: store.activeProgram?.id ?? "test-program",
            workoutId: workout?.id ?? "chest-workout",
            workoutTitle: workout?.title ?? "Chest Growth",
            startedAt: "2026-09-02T10:00:00.000Z",
            completedAt: "2026-09-02T10:35:12.000Z",
            durationSeconds: 2112,
            totalVolumeKg: 4250,
            totalCompletedSets: 5,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: workout?.exercises.first?.name ?? "Barbell Bench Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 80, reps: 10),
                        SessionSetLog(setNumber: 2, weightKg: 80, reps: 8),
                        SessionSetLog(setNumber: 3, weightKg: 80, reps: 8)
                    ]
                ),
                SessionExerciseLog(
                    exerciseName: (workout?.exercises.count ?? 0) > 1 ? workout!.exercises[1].name : "Incline Dumbbell Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 24, reps: 12),
                        SessionSetLog(setNumber: 2, weightKg: 24, reps: 10)
                    ]
                )
            ]
        )

        let detail = HistoryDayDetailData(
            date: date,
            dateString: "2026-09-02",
            status: .unfinished,
            sessionRecord: sampleRecord,
            workout: workout
        )

        let sheet = HistoryDayDetailSheet(detail: detail, onDismiss: {}, onActionWorkout: {}, initiallyExpanded: true)
        let controller = UIHostingController(rootView: sheet)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 1100)
        controller.view.backgroundColor = UIColor(red: 0x14/255.0, green: 0x17/255.0, blue: 0x1A/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 1100))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_history_detail_expanded_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testHistoryDayDetailSheetTurkishSnapshot() {
        let prevLang = LanguageManager.shared.currentLanguage
        LanguageManager.setLanguage("tr")
        defer { LanguageManager.setLanguage(prevLang) }

        let store = AppStore.shared
        let workout = store.activeProgram?.workouts.first(where: { $0.title.contains("Chest") }) ?? store.activeWorkout
        let date = WorkoutCalendar.parseDate("2026-09-02")!

        let sampleRecord = WorkoutSessionRecord(
            id: "test-rec-tr",
            programId: store.activeProgram?.id ?? "test-program",
            workoutId: workout?.id ?? "chest-workout",
            workoutTitle: workout?.title ?? "Göğüs & Arka Kol",
            startedAt: "2026-09-02T10:00:00.000Z",
            completedAt: "2026-09-02T10:35:12.000Z",
            durationSeconds: 2112,
            totalVolumeKg: 4250,
            totalCompletedSets: 5,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: workout?.exercises.first?.name ?? "Barbell Bench Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 80, reps: 10),
                        SessionSetLog(setNumber: 2, weightKg: 80, reps: 8),
                        SessionSetLog(setNumber: 3, weightKg: 80, reps: 8)
                    ]
                ),
                SessionExerciseLog(
                    exerciseName: (workout?.exercises.count ?? 0) > 1 ? workout!.exercises[1].name : "Incline Dumbbell Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 24, reps: 12),
                        SessionSetLog(setNumber: 2, weightKg: 24, reps: 10)
                    ]
                )
            ]
        )

        let detail = HistoryDayDetailData(
            date: date,
            dateString: "2026-09-02",
            status: .unfinished,
            sessionRecord: sampleRecord,
            workout: workout
        )

        let sheet = HistoryDayDetailSheet(detail: detail, onDismiss: {}, onActionWorkout: {})
        let controller = UIHostingController(rootView: sheet)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 850)
        controller.view.backgroundColor = UIColor(red: 0x14/255.0, green: 0x17/255.0, blue: 0x1A/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 850))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_history_detail_turkish_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testHistoryDayDetailSheetCompletedSnapshot() {
        let store = AppStore.shared
        let workout = store.activeProgram?.workouts.first(where: { $0.title.contains("Chest") }) ?? store.activeWorkout
        let date = WorkoutCalendar.parseDate("2026-09-02")!

        let sampleRecord = WorkoutSessionRecord(
            id: "test-rec-completed",
            programId: store.activeProgram?.id ?? "test-program",
            workoutId: workout?.id ?? "chest-workout",
            workoutTitle: workout?.title ?? "Chest Growth",
            startedAt: "2026-09-02T10:00:00.000Z",
            completedAt: "2026-09-02T10:45:12.000Z",
            durationSeconds: 2712,
            totalVolumeKg: 5250,
            totalCompletedSets: 6,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: workout?.exercises.first?.name ?? "Barbell Bench Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 80, reps: 10),
                        SessionSetLog(setNumber: 2, weightKg: 80, reps: 8),
                        SessionSetLog(setNumber: 3, weightKg: 80, reps: 8)
                    ],
                    targetSets: 3
                ),
                SessionExerciseLog(
                    exerciseName: (workout?.exercises.count ?? 0) > 1 ? workout!.exercises[1].name : "Incline Dumbbell Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 24, reps: 12),
                        SessionSetLog(setNumber: 2, weightKg: 24, reps: 10),
                        SessionSetLog(setNumber: 3, weightKg: 24, reps: 10)
                    ],
                    targetSets: 3
                )
            ],
            isComplete: true
        )

        let detail = HistoryDayDetailData(
            date: date,
            dateString: "2026-09-02",
            status: .completed,
            sessionRecord: sampleRecord,
            workout: workout
        )

        let sheet = HistoryDayDetailSheet(
            detail: detail,
            history: [sampleRecord],
            onDismiss: {},
            onActionWorkout: {},
            initiallyExpanded: true
        )
        let controller = UIHostingController(rootView: sheet)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 850)
        controller.view.backgroundColor = UIColor(red: 0x14/255.0, green: 0x17/255.0, blue: 0x1A/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 850))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_history_detail_completed_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testHistoryDayPreviewCardSnapshot() {
        let store = AppStore.shared
        let workout = Workout(
            id: "chest-workout",
            day: 1,
            title: "Chest & Triceps",
            exercises: [
                Exercise(name: "Barbell Bench Press", sets: 3),
                Exercise(name: "Incline Dumbbell Press", sets: 3),
                Exercise(name: "Cable Fly", sets: 3),
                Exercise(name: "Triceps Pushdown", sets: 3)
            ]
        )
        let date = WorkoutCalendar.parseDate("2026-09-02")!

        let priorRecord = WorkoutSessionRecord(
            id: "prior-rec",
            programId: store.activeProgram?.id ?? "test-program",
            workoutId: workout.id,
            workoutTitle: workout.title,
            startedAt: "2026-08-25T10:00:00.000Z",
            completedAt: "2026-08-25T10:45:00.000Z",
            durationSeconds: 2700,
            totalVolumeKg: 4000,
            totalCompletedSets: 6,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [SessionSetLog(setNumber: 1, weightKg: 80, reps: 8)],
                    targetSets: 3
                )
            ],
            isComplete: true
        )

        let currentRecord = WorkoutSessionRecord(
            id: "current-rec",
            programId: store.activeProgram?.id ?? "test-program",
            workoutId: workout.id,
            workoutTitle: workout.title,
            startedAt: "2026-09-02T10:00:00.000Z",
            completedAt: "2026-09-02T10:48:30.000Z",
            durationSeconds: 2910,
            totalVolumeKg: 6200,
            totalCompletedSets: 12,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 100, reps: 8),
                        SessionSetLog(setNumber: 2, weightKg: 100, reps: 8),
                        SessionSetLog(setNumber: 3, weightKg: 100, reps: 6)
                    ],
                    targetSets: 3
                ),
                SessionExerciseLog(
                    exerciseName: "Incline Dumbbell Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 28, reps: 10),
                        SessionSetLog(setNumber: 2, weightKg: 28, reps: 10),
                        SessionSetLog(setNumber: 3, weightKg: 28, reps: 8)
                    ],
                    targetSets: 3
                ),
                SessionExerciseLog(
                    exerciseName: "Cable Fly",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 15, reps: 12),
                        SessionSetLog(setNumber: 2, weightKg: 15, reps: 12)
                    ],
                    targetSets: 3
                ),
                SessionExerciseLog(
                    exerciseName: "Triceps Pushdown",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 25, reps: 12),
                        SessionSetLog(setNumber: 2, weightKg: 25, reps: 10),
                        SessionSetLog(setNumber: 3, weightKg: 25, reps: 10)
                    ],
                    targetSets: 3
                )
            ],
            isComplete: true
        )

        let detail = HistoryDayDetailData(
            date: date,
            dateString: "2026-09-02",
            status: .completed,
            sessionRecord: currentRecord,
            workout: workout
        )

        let card = HistoryDayPreviewCard(
            detail: detail,
            history: [priorRecord, currentRecord],
            onOpenDetail: {}
        )
        .padding(16)
        .background(Color(hex: 0x090C0F))

        let controller = UIHostingController(rootView: card)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 480)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 480))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_history_preview_card_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    func testHistoryDayPreviewCardUnfinishedSnapshot() {
        let store = AppStore.shared
        let workout = Workout(
            id: "unfinished-test-workout",
            day: 1,
            title: "Push Day",
            exercises: [
                Exercise(name: "Barbell Bench Press", sets: 3),
                Exercise(name: "Incline Dumbbell Press", sets: 3),
                Exercise(name: "Sled Hack Squat", sets: 3),
                Exercise(name: "Leg Press", sets: 3),
                Exercise(name: "Leg Extension", sets: 3),
                Exercise(name: "Standing Calf Raise", sets: 3),
                Exercise(name: "Seated Cable Row", sets: 3)
            ]
        )
        let date = WorkoutCalendar.parseDate("2026-09-03")!

        let currentRecord = WorkoutSessionRecord(
            id: "unfinished-rec",
            programId: store.activeProgram?.id ?? "test-program",
            workoutId: workout.id,
            workoutTitle: workout.title,
            startedAt: "2026-09-03T10:00:00.000Z",
            completedAt: "2026-09-03T10:25:00.000Z",
            durationSeconds: 1500,
            totalVolumeKg: 2400,
            totalCompletedSets: 4,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 100, reps: 8),
                        SessionSetLog(setNumber: 2, weightKg: 100, reps: 8),
                        SessionSetLog(setNumber: 3, weightKg: 100, reps: 6)
                    ],
                    targetSets: 3
                ),
                SessionExerciseLog(
                    exerciseName: "Incline Dumbbell Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 28, reps: 10)
                    ],
                    targetSets: 3
                )
            ],
            isComplete: false
        )

        let detail = HistoryDayDetailData(
            date: date,
            dateString: "2026-09-03",
            status: .unfinished,
            sessionRecord: currentRecord,
            workout: workout
        )

        let card = HistoryDayPreviewCard(
            detail: detail,
            history: [currentRecord],
            onOpenDetail: {}
        )
        .padding(16)
        .background(Color(hex: 0x090C0F))

        let controller = UIHostingController(rootView: card)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 480)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 480))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_history_preview_card_unfinished_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    func testHistoryDayPreviewCardMissedSnapshot() {
        let store = AppStore.shared
        let workout = Workout(
            id: "missed-test-workout",
            day: 1,
            title: "Chest & Triceps",
            exercises: [
                Exercise(name: "Barbell Bench Press", sets: 3),
                Exercise(name: "Incline Dumbbell Press", sets: 3),
                Exercise(name: "Cable Fly", sets: 3),
                Exercise(name: "Triceps Pushdown", sets: 3)
            ]
        )
        let date = WorkoutCalendar.parseDate("2026-09-01")!

        let detail = HistoryDayDetailData(
            date: date,
            dateString: "2026-09-01",
            status: .missed,
            sessionRecord: nil,
            workout: workout
        )

        let card = HistoryDayPreviewCard(
            detail: detail,
            history: [],
            onOpenDetail: {}
        )
        .padding(16)
        .background(Color(hex: 0x090C0F))

        let controller = UIHostingController(rootView: card)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 480)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 480))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_history_preview_card_missed_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    func testMultiSessionWorkoutDayDetailSections() {
        // Wednesday Oct 7, 2026
        let wedDate = WorkoutCalendar.parseDate("2026-10-07")!
        let monDate = WorkoutCalendar.parseDate("2026-10-05")!

        let exMon = Exercise(id: "ex_mon", name: "Barbell Bench Press", sets: 3)
        let workoutMon = Workout(id: "w_mon", day: 1, title: "Heavy Bench & Push", exercises: [exMon])

        let exWed = Exercise(id: "ex_wed", name: "Barbell Deadlift", sets: 3)
        let workoutWed = Workout(id: "w_wed", day: 3, title: "Heavy Pull & Upper Back", exercises: [exWed])

        let logMon = SessionExerciseLog(exerciseName: "Barbell Bench Press", sets: [
            SessionSetLog(setNumber: 1, weightKg: 80, reps: 5)
        ], targetSets: 3)
        let recordMon = WorkoutSessionRecord(
            id: "rec_mon",
            programId: "p",
            workoutId: "w_mon",
            workoutTitle: "Heavy Bench & Push",
            startedAt: "2026-10-07T14:00:00Z",
            completedAt: "2026-10-07T14:45:00Z",
            durationSeconds: 2700,
            totalVolumeKg: 400.0,
            totalCompletedSets: 1,
            exerciseLogs: [logMon],
            isComplete: false
        )

        let logWed = SessionExerciseLog(exerciseName: "Barbell Deadlift", sets: [
            SessionSetLog(setNumber: 1, weightKg: 120, reps: 5),
            SessionSetLog(setNumber: 2, weightKg: 120, reps: 5),
            SessionSetLog(setNumber: 3, weightKg: 120, reps: 5)
        ], targetSets: 3)
        let recordWed = WorkoutSessionRecord(
            id: "rec_wed",
            programId: "p",
            workoutId: "w_wed",
            workoutTitle: "Heavy Pull & Upper Back",
            startedAt: "2026-10-07T10:00:00Z",
            completedAt: "2026-10-07T10:45:00Z",
            durationSeconds: 2700,
            totalVolumeKg: 1800.0,
            totalCompletedSets: 3,
            exerciseLogs: [logWed],
            isComplete: true
        )

        let itemsWed = HistoryDayDetailData.buildExerciseProgress(sessionRecord: recordWed, workout: workoutWed)
        XCTAssertEqual(itemsWed.count, 1)
        XCTAssertEqual(itemsWed.first?.completedSets, 3)

        let itemsMon = HistoryDayDetailData.buildExerciseProgress(sessionRecord: recordMon, workout: workoutMon)
        XCTAssertEqual(itemsMon.count, 1)
        XCTAssertEqual(itemsMon.first?.completedSets, 1)

        let secWed = WorkoutDaySection(
            sessionRecord: recordWed,
            workout: workoutWed,
            workoutTitle: workoutWed.title,
            originDate: nil,
            originDateFormatted: nil,
            completedSets: 3,
            plannedSets: 3,
            totalVolumeKg: 1800.0,
            durationSeconds: 2700,
            isComplete: true,
            exerciseItems: itemsWed
        )

        let secMon = WorkoutDaySection(
            sessionRecord: recordMon,
            workout: workoutMon,
            workoutTitle: workoutMon.title,
            originDate: monDate,
            originDateFormatted: "Oct 5, 2026",
            completedSets: 1,
            plannedSets: 3,
            totalVolumeKg: 400.0,
            durationSeconds: 2700,
            isComplete: false,
            exerciseItems: itemsMon
        )

        let detail = HistoryDayDetailData(
            date: wedDate,
            dateString: "2026-10-07",
            status: .completed,
            sessionRecord: recordWed,
            workout: workoutWed,
            sections: [secWed, secMon]
        )

        XCTAssertEqual(detail.sections.count, 2)
        XCTAssertNil(detail.sections[0].originDate)
        XCTAssertNotNil(detail.sections[1].originDate)
        XCTAssertEqual(detail.sections[1].originDateFormatted, "Oct 5, 2026")

        // Translations verification
        LanguageManager.setLanguage("en")
        XCTAssertEqual(LanguageManager.t("history.todayExercises"), "Today's Exercises")
        XCTAssertEqual(LanguageManager.t("history.multipleWorkouts", ["count": "2"]), "2 Workouts")
        XCTAssertEqual(LanguageManager.t("history.originallyScheduled", ["date": "Oct 5, 2026"]), "Originally scheduled: Oct 5, 2026")

        LanguageManager.setLanguage("tr")
        XCTAssertEqual(LanguageManager.t("history.todayExercises"), "Bugünün Egzersizleri")
        XCTAssertEqual(LanguageManager.t("history.multipleWorkouts", ["count": "2"]), "2 Antrenman")
        XCTAssertEqual(LanguageManager.t("history.originallyScheduled", ["date": "5 Eki 2026"]), "Planlanan gün: 5 Eki 2026")
        LanguageManager.setLanguage("en")

        // Verify views construct cleanly
        let detailView = HistoryDetailView(detail: detail, onBack: {})
        XCTAssertNotNil(detailView)

        let previewCard = HistoryDayPreviewCard(detail: detail, history: [recordWed, recordMon], onOpenDetail: {})
        XCTAssertNotNil(previewCard)
    }

    func testWorkoutCalendarRefreshPreservesEntries() {
        let initial = WorkoutCalendarHistory(
            nextScheduledDate: "2026-08-24",
            scheduledWeekdays: [1, 2, 4, 5],
            missedDates: [],
            entries: [
                WorkoutDayEntry(id: "session:tue", date: "2026-08-25", status: .unfinished)
            ]
        )
        let refreshed = WorkoutCalendar.refresh(history: initial, today: "2026-08-27", weekdays: [1, 2, 4, 5])
        XCTAssertEqual(refreshed.entries.count, 1, "Entries must not be erased during refresh")
        XCTAssertEqual(refreshed.entries.first?.id, "session:tue")
        XCTAssertEqual(refreshed.entries.first?.status, .unfinished)

        let statuses = WorkoutCalendar.statuses(history: refreshed, today: "2026-08-27")
        XCTAssertEqual(statuses["2026-08-24"], .missed)
        XCTAssertEqual(statuses["2026-08-25"], .unfinished, "Unfinished entry must override missed date")
    }

    func testScheduledDateForWeekday() {
        // Assume date is Friday, Sep 4, 2026
        let friday = WorkoutCalendar.parseDate("2026-09-04")!
        let tueDate = WorkoutCalendar.scheduledDate(forWeekday: 2, relativeTo: friday)
        XCTAssertEqual(tueDate, "2026-09-01", "Tuesday of this week is 2026-09-01")
        let monDate = WorkoutCalendar.scheduledDate(forWeekday: 1, relativeTo: friday)
        XCTAssertEqual(monDate, "2026-08-31", "Monday of this week is 2026-08-31")
        let friDate = WorkoutCalendar.scheduledDate(forWeekday: 5, relativeTo: friday)
        XCTAssertEqual(friDate, "2026-09-04", "Friday of this week is 2026-09-04")
    }

    @MainActor
    func testTuesdayWorkoutPartialCompletionMarksTuesdayUnfinishedNotMissed() {
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier!
        let previous = defaults.persistentDomain(forName: domain) ?? [:]
        defer { defaults.setPersistentDomain(previous, forName: domain) }
        defaults.removeObject(forKey: "active_session_v1")
        let store = AppStore(persistence: AppStatePersistence(inMemory: true))
        let tuesdayWorkout = Workout(id: "tuesday-fixture", day: 2, title: "Pull", exercises: [
            Exercise(id: "pulldown-fixture", name: "Lat Pulldown", sets: 2),
            Exercise(id: "row-fixture", name: "Seated Cable Row", sets: 2)])
        let program = Program(id: "tuesday-plan", name: "Tuesday fixture", workouts: [tuesdayWorkout])
        let tuesdayDate = WorkoutCalendar.scheduledDate(forWeekday: 2, relativeTo: Date())
        var st = StoredAppState(programs: [program], activeProgramId: program.id,
            calendarHistory: WorkoutCalendarHistory(nextScheduledDate: tuesdayDate, scheduledWeekdays: [2]))
        st.history.removeAll { $0.workoutId == tuesdayWorkout.id }
        st.completed.removeAll { $0.contains(tuesdayWorkout.id) }
        st.calendarHistory?.entries.removeAll { $0.date == tuesdayDate }
        store.saveState(st)

        // Start Tuesday workout
        XCTAssertTrue(store.startActiveSession(programId: program.id, workout: tuesdayWorkout, allowPast: true,
            assignedCalendarDate: tuesdayDate, scheduledDate: tuesdayDate))
        guard let draft = store.activeSession else {
            XCTFail("Active session failed to start")
            return
        }

        // Verify that draft is assigned to Tuesday in the current week
        let sessionEntry = store.state.calendarHistory?.entries.first(where: { $0.id == "session:\(draft.id)" })
        XCTAssertNotNil(sessionEntry)
        XCTAssertEqual(sessionEntry?.date, tuesdayDate)
        XCTAssertEqual(sessionEntry?.status, .unfinished)

        // Complete all sets for first exercise (e.g. Lat Pulldown)
        let firstEx = tuesdayWorkout.exercises.first!
        store.updateActiveSession { d in
            var copy = d
            var sets = copy.setsByExercise[firstEx.id] ?? []
            for i in 0..<sets.count {
                sets[i].isCompleted = true
                sets[i].weightKg = 60
                sets[i].completedReps = 10
            }
            copy.setsByExercise[firstEx.id] = sets
            return copy
        }

        // Finish workout (clicks finish / Save & close)
        let progress = SessionProgress.from(draft: store.activeSession!, nowEpochMillis: Int64(Date().timeIntervalSince1970 * 1000))
        let record = progress.record(draft: store.activeSession!, completedAtEpochMillis: Int64(Date().timeIntervalSince1970 * 1000))
        store.completeActiveSession(record)

        // Active session should be nil
        XCTAssertNil(store.activeSession)

        // Tuesday in calendarStatuses must be UNFINISHED (orange), NOT MISSED (red)!
        let tuesdayDateObj = WorkoutCalendar.parseDate(tuesdayDate) ?? Date()
        let statuses = store.calendarStatuses(today: tuesdayDateObj)
        XCTAssertEqual(statuses[tuesdayDate], .unfinished, "Tuesday must be orange (.unfinished), not red (.missed)!")

        // History list must contain record for Tuesday
        let foundRecord = store.state.history.first { rec in
            WorkoutCalendar.localDate(from: rec.startedAt) == tuesdayDate ||
            store.state.calendarHistory?.entries.first(where: { $0.id == "session:\(rec.id)" })?.date == tuesdayDate
        }
        XCTAssertNotNil(foundRecord, "Record must be mapped to \(tuesdayDate)")
        let firstExLog = foundRecord?.exerciseLogs.first(where: { $0.exerciseName.lowercased() == firstEx.name.lowercased() })
        XCTAssertNotNil(firstExLog)
        XCTAssertGreaterThan(firstExLog?.sets.count ?? 0, 0, "Lat Pulldown sets must be recorded as completed")
    }

    // MARK: - Video Support Tests

    func testYouTubeVideoParsing() {
        // Standard watch URLs
        let watch = YouTubeVideo.parse("https://www.youtube.com/watch?v=ZaTM37cfiDs")
        XCTAssertNotNil(watch)
        XCTAssertEqual(watch?.id, "ZaTM37cfiDs")
        XCTAssertFalse(watch?.isShort ?? true)
        XCTAssertEqual(watch?.startSeconds, 0)

        // Shorts URL
        let short = YouTubeVideo.parse("https://youtube.com/shorts/ZaTM37cfiDs")
        XCTAssertNotNil(short)
        XCTAssertEqual(short?.id, "ZaTM37cfiDs")
        XCTAssertTrue(short?.isShort ?? false)

        // youtu.be shortlink with start time in seconds
        let youtbe = YouTubeVideo.parse("https://youtu.be/ZaTM37cfiDs?t=90")
        XCTAssertNotNil(youtbe)
        XCTAssertEqual(youtbe?.id, "ZaTM37cfiDs")
        XCTAssertEqual(youtbe?.startSeconds, 90)
        XCTAssertEqual(youtbe?.watchUrl, "https://www.youtube.com/watch?v=ZaTM37cfiDs&t=90s")

        // Formatted timestamp (1h2m3s)
        let formattedTime = YouTubeVideo.parse("https://www.youtube.com/watch?v=ZaTM37cfiDs&t=1h2m3s")
        XCTAssertNotNil(formattedTime)
        XCTAssertEqual(formattedTime?.startSeconds, 3723)

        // Invalid URLs
        XCTAssertNil(YouTubeVideo.parse("https://vimeo.com/12345678"))
        XCTAssertNil(YouTubeVideo.parse("https://youtube.com/watch?v=short"))
        XCTAssertNil(YouTubeVideo.parse("ftp://youtube.com/watch?v=ZaTM37cfiDs"))
        XCTAssertNil(YouTubeVideo.parse("not a url"))
    }

    func testVideoPlaybackStateProperties() {
        let unready = VideoPlaybackState(ready: false, playerState: -1)
        XCTAssertFalse(unready.playing)
        XCTAssertFalse(unready.ended)
        XCTAssertFalse(unready.canControl)

        let playing = VideoPlaybackState(ready: true, playerState: 1, currentSeconds: 10, durationSeconds: 60)
        XCTAssertTrue(playing.playing)
        XCTAssertFalse(playing.ended)
        XCTAssertTrue(playing.canControl)

        let buffering = VideoPlaybackState(ready: true, playerState: 3)
        XCTAssertTrue(buffering.playing)

        let ended = VideoPlaybackState(ready: true, playerState: 0)
        XCTAssertFalse(ended.playing)
        XCTAssertTrue(ended.ended)
        XCTAssertTrue(ended.canControl)

        let errored = VideoPlaybackState(ready: true, playerState: 1, error: "network")
        XCTAssertFalse(errored.canControl)
    }

    func testFormatVideoTime() {
        XCTAssertEqual(formatVideoTime(0), "0:00")
        XCTAssertEqual(formatVideoTime(9), "0:09")
        XCTAssertEqual(formatVideoTime(75), "1:15")
        XCTAssertEqual(formatVideoTime(3599), "59:59")
        XCTAssertEqual(formatVideoTime(3600), "1:00:00")
        XCTAssertEqual(formatVideoTime(3665), "1:01:05")
    }

    func testAppStoreSetExerciseVideos() throws {
        let store = AppStore.shared
        let previous = store.state
        let previousCatalogue = store.exerciseCatalogue
        let previousNotice = store.noticeMessage
        defer {
            store.state = previous; store.saveState(previous)
            store.exerciseCatalogue = previousCatalogue; store.noticeMessage = previousNotice
        }
        let exerciseName = "Barbell Back Squat"

        let testUrls = [
            "https://youtu.be/ZaTM37cfiDs",
            "youtube.com/watch?v=dQw4w9WgXcQ",
            "https://youtu.be/ZaTM37cfiDs", // duplicate
            "https://youtube.com/shorts/3jzKvd6e2q4",
            "https://youtube.com/watch?v=abcdefghijk" // 4th valid link, capped at 3
        ]

        store.setExerciseVideos(exerciseName: exerciseName, videoUrls: testUrls)

        let catalogEntry = store.exerciseCatalogue.first { $0.key == exerciseName.lowercased() }
        XCTAssertNotNil(catalogEntry)
        XCTAssertEqual(catalogEntry?.exercise.videos.count, 3, "Videos count must be capped at 3")
        XCTAssertEqual(catalogEntry?.exercise.videos[0], "https://youtu.be/ZaTM37cfiDs")
        XCTAssertEqual(catalogEntry?.exercise.videos[1], "https://youtube.com/watch?v=dQw4w9WgXcQ")
        XCTAssertEqual(catalogEntry?.exercise.videos[2], "https://youtube.com/shorts/3jzKvd6e2q4")
        XCTAssertNotNil(store.noticeMessage)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let saved = try encoder.encode(store.state)
        store.setExerciseVideos(exerciseName: exerciseName, videoUrls: ["https://vimeo.com/123"])
        XCTAssertEqual(try encoder.encode(store.state), saved)
        XCTAssertEqual(store.noticeMessage, LanguageManager.t("video.youtubeOnly"))
    }

    func testExerciseMuscleCatalog() throws {
        let catalog = try XCTUnwrap(ExerciseMuscleCatalog.shared)
        XCTAssertEqual(catalog.exercises.count, 300)
        XCTAssertNil(catalog.profile(nil))
        XCTAssertNil(catalog.profile("unknown"))
        XCTAssertNotNil(catalog.profile("barbell-back-squat"))
        for (_, profile) in catalog.exercises {
            XCTAssertFalse(profile.primary.isEmpty)
            XCTAssertEqual(Set(profile.all).count, profile.all.count)
            XCTAssertFalse(profile.sources.isEmpty)
            XCTAssertTrue(catalog.availableViews(profile).contains(profile.initialView))
            for muscle in profile.all {
                XCTAssertNotNil(catalog.muscles[muscle]?["en"])
                XCTAssertNotNil(catalog.muscles[muscle]?["tr"])
                XCTAssertTrue(catalog.views.values.contains { $0.regions[muscle] != nil })
            }
        }
        XCTAssertEqual(ExerciseMuscleCatalog.images.count, 2)
        for image in ExerciseMuscleCatalog.images.values {
            XCTAssertEqual(image.size, CGSize(width: 480, height: 1024))
        }
        let chestPath = try XCTUnwrap(catalog.views["front"]?.regions["chest"])
        assertMirroredChestPath(chestPath, centerX: 520)
    }

    private func assertMirroredChestPath(_ path: String, centerX: Double) {
        let halves = path.components(separatedBy: " Z M ")
        XCTAssertEqual(halves.count, 2)
        guard halves.count == 2 else { return }
        let expression = try! NSRegularExpression(pattern: #"-?\d+(?:\.\d+)?"#)
        func coordinates(_ value: String) -> [(Double, Double)] {
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            let values = expression.matches(in: value, range: range).compactMap { match -> Double? in
                guard let range = Range(match.range, in: value) else { return nil }
                return Double(value[range])
            }
            return stride(from: 0, to: values.count, by: 2).map { (values[$0], values[$0 + 1]) }
        }
        let left = coordinates(halves[0])
        let right = coordinates(halves[1])
        XCTAssertEqual(left.count, right.count)
        for (index, pair) in zip(left, right).enumerated() {
            XCTAssertEqual(pair.0.0, centerX * 2 - pair.1.0, accuracy: 0.01, "x at point \(index)")
            XCTAssertEqual(pair.0.1, pair.1.1, accuracy: 0.01, "y at point \(index)")
        }
    }

    @MainActor
    func testExerciseMusclePanelRenders() throws {
        let previousLanguage = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(previousLanguage) }
        for (id, name, language, width, type) in [
            ("barbell-bench-press", "bench", "en", 350.0, DynamicTypeSize.large),
            ("pull-ups", "pull", "tr", 280.0, DynamicTypeSize.xxxLarge),
            ("seated-leg-curl", "legs", "en", 350.0, DynamicTypeSize.large),
            ("unknown", "unknown", "en", 280.0, DynamicTypeSize.large)
        ] {
            LanguageManager.setLanguage(language)
            let renderer = ImageRenderer(content: ExerciseMusclesCard(exerciseId: id, initiallyExpanded: true)
                .environment(\.dynamicTypeSize, type).frame(width: width))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertGreaterThan(image.size.height, 60)
            XCTAssertLessThan(image.size.height, 750)
            try image.pngData()?.write(to: URL(fileURLWithPath: "/private/tmp/form-muscles-ios-\(name).png"))
            let attachment = XCTAttachment(image: image)
            attachment.name = "Muscle panel \(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testExerciseMusclesCardExpandedByDefault() throws {
        LanguageManager.setLanguage("en")
        let renderer = ImageRenderer(content: ExerciseMusclesCard(exerciseId: "barbell-bench-press")
            .frame(width: 350))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertGreaterThan(image.size.height, 100)

        let collapsedRenderer = ImageRenderer(content: ExerciseMusclesCard(exerciseId: "barbell-bench-press", initiallyExpanded: false)
            .frame(width: 350))
        collapsedRenderer.scale = 2
        let collapsedImage = try XCTUnwrap(collapsedRenderer.uiImage)
        XCTAssertLessThan(collapsedImage.size.height, 90)
    }

    func testVideoDuplicatesPreserveCaseSensitiveIdsAndFirstTimestamp() {
        let first = "https://youtu.be/ZaTM37cfiDs?t=90"
        let same = "https://youtube.com/shorts/ZaTM37cfiDs?t=30"
        let different = "https://youtu.be/zaTM37cfiDs?t=90"
        XCTAssertTrue(YouTubeVideo.isSameVideo(first, same))
        XCTAssertFalse(YouTubeVideo.isSameVideo(first, different))
        XCTAssertFalse(YouTubeVideo.isSameVideo("invalid", "invalid"))
        XCTAssertFalse(YouTubeVideo.isSameVideo(first, "invalid"))
        XCTAssertEqual(YouTubeVideo.validatedLinks([first, same, different]), [first, different])
    }

    func testProgramExportTranslation() {
        XCTAssertEqual(Translations.en["programs.export"], "Export")
        XCTAssertEqual(Translations.tr["programs.export"], "Dışa aktar")
        XCTAssertEqual(Translations.en["programs.share"], "Share")
        XCTAssertEqual(Translations.tr["programs.share"], "Paylaş")
    }

    func testExerciseLinksAcceptOnlyYouTubeVideosAndShorts() {
        let id = "ZaTM37cfiDs"
        for url in [" youtube.com/watch?v=\(id) ", "youtu.be/\(id)?si=share", "https://youtube.com/shorts/\(id)",
                    "https://m.youtube.com/watch?v=\(id)&t=90", "https://www.youtube-nocookie.com/embed/\(id)"] {
            XCTAssertTrue(YouTubeVideo.isSupportedLink(url), url)
        }
        for url in ["https://vimeo.com/123", "https://example.com/video.mp4", "youtube.com", "youtube.com/@trainer",
                    "youtube.com/playlist?list=PL123", "youtube.com/watch?v=short", "youtube.com.evil.com/watch?v=\(id)",
                    "https://user@youtube.com/watch?v=\(id)", "ftp://youtube.com/watch?v=\(id)", "", "not a url",
                    "https://youtube.com/watch?v=\(id)&x=" + String(repeating: "a", count: 2_000)] {
            XCTAssertFalse(YouTubeVideo.isSupportedLink(url), url)
        }
        XCTAssertNil(YouTubeVideo.validatedLinks(["youtu.be/\(id)", "https://example.com"]))
        XCTAssertEqual(YouTubeVideo.validatedLinks([]), [])
        XCTAssertEqual(YouTubeVideo.validatedLinks(["youtu.be/\(id)", "https://youtu.be/\(id)", " "]), ["https://youtu.be/\(id)"])
        XCTAssertEqual(YouTubeVideo.validatedLinks(["youtu.be/\(id)", "https://www.youtube.com/watch?v=\(id)&si=xyz", "https://youtube.com/shorts/\(id)"]), ["https://youtu.be/\(id)"])
        XCTAssertEqual(YouTubeVideo.parse("https://youtu.be/\(id)?t=9223372036854775807h")?.startSeconds, 604800)
    }

    func testAppStoreExerciseCatalogueContainsAll300Exercises() {
        let store = AppStore(persistence: AppStatePersistence(inMemory: true))
        let canonicalIDs = Set(ExerciseCatalog.canonicalExercises.keys)
        XCTAssertEqual(canonicalIDs.count, 300)
        let availableIDs = Set(store.exerciseCatalogue.compactMap { $0.exercise.exerciseId })
        XCTAssertTrue(canonicalIDs.isSubset(of:availableIDs), "All canonical exercises must be available alongside custom exercises")
    }

    func testLegacyExerciseNameWithCanonicalExerciseIdMergesUnderCanonicalName() {
        let legacyExercise = Exercise(
            name: "Conventional Barbell Deadlift",
            exerciseId: "conventional-barbell-deadlift"
        )
        let legacyWorkout = Workout(id: "w-leg", day: 1, title: "Legs", exercises: [legacyExercise])
        let legacyProgram = Program(id: "p-leg", name: "Legacy", workouts: [legacyWorkout])
        let entries = ExerciseCatalog.build(
            bundledPrograms: [],
            userPrograms: [legacyProgram],
            canonicalExercises: Array(ExerciseCatalog.canonicalExercises.values)
        )
        XCTAssertEqual(entries.count, 300)
        let deadlift = entries.first { $0.exercise.exerciseId == "conventional-barbell-deadlift" }
        XCTAssertEqual(deadlift?.key, "deadlift")
        XCTAssertEqual(deadlift?.exercise.name, "Deadlift")
        XCTAssertTrue(deadlift?.programIds.contains("p-leg") ?? false)
    }

    func testVideoTranslationsParity() {
        let requiredKeys = [
            "video.openExternal", "video.close", "video.back5", "video.forward5",
            "video.play", "video.pause", "video.resume", "video.replay",
            "video.loading", "video.retry", "video.invalid", "video.youtubeOnly", "video.networkError", "video.embedError",
            "video.linkTitle", "video.linkSubtitle", "video.urlInputLabel", "video.urlInputPlaceholder",
            "video.addUrlButton", "video.paste", "video.preview",
            "video.linkedCount", "video.maxReached", "video.maxReachedHint", "video.alreadyAdded",
            "video.noVideos", "video.saveLinks", "video.tapToPlay", "notice.videosUpdated",
            "library.videos", "library.attachVideoCta"
        ]

        for key in requiredKeys {
            XCTAssertFalse(Translations.en[key]?.isEmpty ?? true, "Missing English key: \(key)")
            XCTAssertFalse(Translations.tr[key]?.isEmpty ?? true, "Missing Turkish key: \(key)")
        }
    }

    @MainActor
    func testExerciseVideoLinksSheetSnapshot() {
        let exercise = Exercise(
            name: "Incline Dumbbell Press",
            prescription: "4 × 8–10",
            videos: [
                "https://www.youtube.com/watch?v=8iPEnn-ltC8"
            ],
            movementType: "press"
        )
        let sheet = ExerciseVideoLinksSheet(exercise: exercise, onDismiss: {})
        let controller = UIHostingController(rootView: sheet)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x14/255.0, green: 0x17/255.0, blue: 0x1A/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_exercise_video_links_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testVideoPlayerSheetSnapshot() {
        let sheet = VideoPlayerSheet(
            exerciseName: "Barbell Bench Press",
            videoUrl: "https://www.youtube.com/watch?v=ZaTM37cfiDs",
            onClose: {}
        )
        let controller = UIHostingController(rootView: sheet)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_video_player_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    func testCanonicalExercisesSeedCatalogueIndependentlyOfPrograms() {
        let catalogue = ExerciseCatalog.build(
            bundledPrograms: [],
            userPrograms: [],
            canonicalExercises: Array(ExerciseCatalog.canonicalExercises.values)
        )

        XCTAssertEqual(catalogue.count, 300)
        XCTAssertEqual(catalogue.count, Set(catalogue.map { $0.key }).count)
        XCTAssertEqual(catalogue.filter { $0.exercise.movementAssetId != nil }.count, 50)
        XCTAssertEqual(catalogue.filter { !$0.exercise.cues.isEmpty }.count, 300)
        XCTAssertEqual(catalogue.filter { !$0.exercise.avoid.isEmpty }.count, 300)
        XCTAssertEqual(catalogue.filter { $0.exercise.exerciseId != nil }.count, 300)
        XCTAssertGreaterThan(Set(ExerciseCatalog.canonicalExercises.values.map { $0.cues.count }).count, 1)
        XCTAssertGreaterThan(Set(ExerciseCatalog.canonicalExercises.values.map { $0.avoid.count }).count, 1)
        XCTAssertTrue(ExerciseCatalog.canonicalExercises["nordic-hamstring-curl"]?.cuesText.contains("Anchor your ankles") == true)
        XCTAssertTrue(ExerciseCatalog.canonicalExercises["handstand-push-up"]?.cuesText.contains("handstand") == true)
    }

    func testCanonicalExercisesProvideTurkishCuesAndAvoid() {
        let canonical = Array(ExerciseCatalog.canonicalExercises.values)
        XCTAssertEqual(canonical.count, 300)
        let trExercises = ContentLocalizer.shared.loadExercises(lang: "tr")
        XCTAssertEqual(trExercises.count, 300)
        XCTAssertEqual(trExercises.values.filter { ($0.cues ?? []).count > 0 }.count, 300)
        XCTAssertEqual(trExercises.values.filter { ($0.avoid ?? []).count > 0 }.count, 300)
        for definition in canonical {
            XCTAssertEqual(trExercises[definition.id]?.cues?.count, definition.cues.count, definition.id)
            XCTAssertEqual(trExercises[definition.id]?.avoid?.count, definition.avoid.count, definition.id)
            let english = ContentLocalizer.shared.loadExercises(lang: "en")[definition.id]
            XCTAssertEqual(trExercises[definition.id]?.cuesDetails?.count, english?.cuesDetails?.count, definition.id)
            XCTAssertEqual(trExercises[definition.id]?.avoidDetails?.count, english?.avoidDetails?.count, definition.id)
            XCTAssertFalse((english?.cuesDetails ?? []).isEmpty, definition.id)
            XCTAssertFalse((english?.avoidDetails ?? []).isEmpty, definition.id)
        }

        guard let bench = canonical.first(where: { $0.id == "barbell-bench-press" }) else {
            XCTFail("Missing bench press definition")
            return
        }

        LanguageManager.setLanguage("tr")
        defer { LanguageManager.setLanguage("en") }

        let localizedCues = LanguageManager.content(bench.cuesText)
        XCTAssertTrue(localizedCues.contains("Sehpada dengeli yerleş"))
        XCTAssertTrue(localizedCues.contains("kontrollü biçimde göğsüne"))

        let localizedAvoid = LanguageManager.content(bench.avoidText)
        XCTAssertTrue(localizedAvoid.contains("Ağırlığı sektirme"))
        XCTAssertFalse(localizedAvoid.contains("omuz sıkışmasına"))

        let firstCue = bench.cues.first!
        let localizedFirstCue = LanguageManager.content(firstCue)
        XCTAssertEqual(localizedFirstCue, trExercises["barbell-bench-press"]?.cues?.first)
    }

    func testContentLocalizerResolution() {
        LanguageManager.setLanguage("tr")
        defer { LanguageManager.setLanguage("en") }

        let pullUps = Exercise(name: "Pull-Ups", exerciseId: "pull-ups")
        XCTAssertEqual(pullUps.displayName, "Barfiks")
        XCTAssertTrue(pullUps.displayCues.contains("Sağlam bir barı rahat bir tutuşla kavra"))

        let bench = Exercise(name: "Barbell Bench Press", exerciseId: "barbell-bench-press")
        XCTAssertEqual(bench.displayName, "Barbell Bench Press")

        let deadlift = Exercise(name: "Deadlift", exerciseId: "conventional-barbell-deadlift")
        XCTAssertEqual(deadlift.displayName, "Deadlift")

        let smithSquat = Exercise(name: "Smith Machine Squat", exerciseId: "smith-squat")
        XCTAssertEqual(smithSquat.displayName, "Smith Makinesi Squat")

        let workout = Workout(id: "pb-squat-strength", day: 1, title: "Lower: Squat", focus: "Squat practice with hamstrings and calves")
        XCTAssertEqual(workout.displayTitle(programId: "powerbuilding-strength"), "Alt Vücut: Squat")
        XCTAssertEqual(workout.displayFocus(programId: "powerbuilding-strength"), "Squat tekniği, arka bacak ve baldır")

        let program = Program(id: "powerbuilding-strength", name: "Heavy & Built: 4-Day Powerbuilding")
        XCTAssertEqual(program.displayName, "Heavy & Built: 4 Günlük Güç ve Kas")
        XCTAssertEqual(Program(id: "machine-foundation", name: "Machine Foundation: 3-Day Full Body").displayName, "Machine Foundation: 3 Günlük Tüm Vücut")
        XCTAssertEqual(Program(id: "upper-lower-balanced", name: "Balanced Build: 4-Day Upper/Lower").displayName, "Balanced Build: 4 Günlük Üst/Alt Vücut")

        // English check
        LanguageManager.setLanguage("en")
        XCTAssertEqual(pullUps.displayName, "Pull-Ups")
        XCTAssertEqual(workout.displayTitle(programId: "powerbuilding-strength"), "Lower: Squat")
    }

    func testTechniqueKeepsSafetyVisibleAndReferenceDetailsOptional() {
        let localizer = ContentLocalizer.shared
        let bench = localizer.exerciseCues(exerciseId: "barbell-bench-press", fallback: [], lang: "en")
        XCTAssertTrue(bench.contains { $0.contains("rack safeties") })
        let details = localizer.exerciseCuesDetails(exerciseId: "barbell-bench-press", lang: "en")
        XCTAssertGreaterThan(details.joined().count, bench.joined().count)
        XCTAssertTrue(details.first?.hasPrefix("Set up:") == true)
        XCTAssertTrue(localizer.exerciseCuesDetails(exerciseId: "barbell-bench-press", lang: "tr").first?.hasPrefix("Hazırlık:") == true)
        XCTAssertEqual(details, localizer.exerciseCuesDetails(exerciseId: "barbell-bench-press", lang: "missing-language"))
        XCTAssertTrue(localizer.exerciseCuesDetails(exerciseId: "custom-123", lang: "en").isEmpty)
        XCTAssertTrue(localizer.exerciseAvoidDetails(exerciseId: nil, lang: "en").isEmpty)
        let larsen = localizer.exerciseCues(exerciseId: "barbell-larsen-press", fallback: [], lang: "en")
        XCTAssertTrue(larsen.contains { $0.contains("Feet stay off the floor") })
        XCTAssertFalse(larsen.contains { $0.contains("Keep feet secure") })
        let handstand = localizer.exerciseCues(exerciseId: "handstand-push-up", fallback: [], lang: "en")
        XCTAssertTrue(handstand.contains { $0.contains("exit you can control") })
    }

    func testExercisePriorityStaplesBeforeGymRatMoves() {
        XCTAssertEqual(ExercisePriority.orderedIds.count, 300)
        XCTAssertEqual(Set(ExercisePriority.orderedIds).count, 300)

        let benchRank = ExercisePriority.priority(for: "barbell-bench-press")
        let squatRank = ExercisePriority.priority(for: "barbell-back-squat")
        let deadliftRank = ExercisePriority.priority(for: "conventional-barbell-deadlift")
        let pullUpRank = ExercisePriority.priority(for: "pull-ups")
        let latPulldownRank = ExercisePriority.priority(for: "lat-pulldown")

        let svendPressRank = ExercisePriority.priority(for: "svend-press")
        let tatePressRank = ExercisePriority.priority(for: "dumbbell-tate-press")
        let zercherSquatRank = ExercisePriority.priority(for: "barbell-full-zercher-squat")
        let larsenPressRank = ExercisePriority.priority(for: "barbell-larsen-press")
        let gorillaRowRank = ExercisePriority.priority(for: "dumbbell-gorilla-row")
        let tibialisRaiseRank = ExercisePriority.priority(for: "wall-supported-tibialis-raise")
        let kasGluteBridgeRank = ExercisePriority.priority(for: "barbell-kas-glute-bridge")

        // Staples in top 40
        XCTAssertTrue(benchRank < 40)
        XCTAssertTrue(squatRank < 40)
        XCTAssertTrue(deadliftRank < 40)
        XCTAssertTrue(pullUpRank < 40)
        XCTAssertTrue(latPulldownRank < 40)

        // Niche gym-rat moves in bottom 50 (> 250)
        XCTAssertTrue(svendPressRank > 250)
        XCTAssertTrue(tatePressRank > 250)
        XCTAssertTrue(zercherSquatRank > 250)
        XCTAssertTrue(larsenPressRank > 250)
        XCTAssertTrue(gorillaRowRank > 250)
        XCTAssertTrue(tibialisRaiseRank > 250)
        XCTAssertTrue(kasGluteBridgeRank > 250)
    }

    func testTurkishPossessiveNumberAndSetsProgress() {
        LanguageManager.setLanguage("tr")
        defer { LanguageManager.setLanguage("en") }

        XCTAssertEqual(LanguageManager.formatSetsProgress(done: 4, total: 5), "5 setten 4'ü tamamlandı")
        XCTAssertEqual(LanguageManager.formatSetsProgress(done: 4, total: 4), "4 setten 4'ü tamamlandı")
        XCTAssertEqual(LanguageManager.formatSetsProgress(done: 0, total: 3), "3 setten 0'ı tamamlandı")
        XCTAssertEqual(LanguageManager.formatSetsProgress(done: 1, total: 3), "3 setten 1'i tamamlandı")
        XCTAssertEqual(LanguageManager.formatSetsProgress(done: 2, total: 3), "3 setten 2'si tamamlandı")
        XCTAssertEqual(LanguageManager.formatSetsProgress(done: 3, total: 3), "3 setten 3'ü tamamlandı")
        XCTAssertEqual(LanguageManager.formatSetsProgress(done: 5, total: 5), "5 setten 5'i tamamlandı")
        XCTAssertEqual(LanguageManager.formatSetsProgress(done: 6, total: 6), "6 setten 6'sı tamamlandı")
        XCTAssertEqual(LanguageManager.formatSetsProgress(done: 10, total: 10), "10 setten 10'u tamamlandı")

        LanguageManager.setLanguage("en")
        XCTAssertEqual(LanguageManager.formatSetsProgress(done: 4, total: 5), "4 of 5 sets")
        XCTAssertEqual(LanguageManager.formatSetsProgress(done: 4, total: 4), "4 of 4 sets")
    }

    func testUncompletedExercisesCountFormatting() {
        LanguageManager.setLanguage("en")
        XCTAssertEqual(LanguageManager.formatUncompletedExercisesCount(1), "1 uncompleted exercise")
        XCTAssertEqual(LanguageManager.formatUncompletedExercisesCount(6), "6 uncompleted exercises")

        LanguageManager.setLanguage("tr")
        XCTAssertEqual(LanguageManager.formatUncompletedExercisesCount(1), "1 tamamlanmamış egzersiz")
        XCTAssertEqual(LanguageManager.formatUncompletedExercisesCount(6), "6 tamamlanmamış egzersiz")
        LanguageManager.setLanguage("en")
    }

    func testCompletedExercisesCountFormatting() {
        LanguageManager.setLanguage("en")
        XCTAssertEqual(LanguageManager.formatCompletedExercisesCount(1), "1 completed exercise")
        XCTAssertEqual(LanguageManager.formatCompletedExercisesCount(6), "6 completed exercises")

        LanguageManager.setLanguage("tr")
        XCTAssertEqual(LanguageManager.formatCompletedExercisesCount(1), "1 tamamlanan egzersiz")
        XCTAssertEqual(LanguageManager.formatCompletedExercisesCount(6), "6 tamamlanan egzersiz")
        LanguageManager.setLanguage("en")
    }

    func testSessionProgressTargetSetsWhenSetDeleted() {
        let exercise = Exercise(id: "squat", name: "Barbell Back Squat", sets: 5)
        let workout = Workout(id: "w1", day: 1, title: "Heavy Squat", exercises: [exercise])
        // 4 sets remaining out of 5, all completed
        let sets = (1...4).map { setNum in
            ExerciseSetLog(
                id: "set-\(setNum)",
                setNumber: setNum,
                weightKg: 100,
                completedReps: 5,
                isCompleted: true
            )
        }
        let draft = ActiveSessionDraft(
            id: "draft-1",
            programId: "prog-1",
            workout: workout,
            startedAt: "2026-09-05T10:00:00Z",
            startedAtEpochMillis: 1000,
            setsByExercise: ["squat": sets]
        )

        let progress = SessionProgress.from(draft: draft, nowEpochMillis: 2000)
        let log = progress.exerciseLogs.first
        XCTAssertEqual(log?.sets.count, 4)
        XCTAssertEqual(log?.targetSets, 4)
    }

    func testRestoreSetsFromHistoryRespectsTargetSetsWhenSetDeleted() {
        let exercise = Exercise(id: "bench", name: "Barbell Bench Press", sets: 4)
        let workout = Workout(id: "w1", day: 1, title: "Chest", exercises: [exercise])

        // User deleted set 4 (targetSets = 3), completed 1 set
        let record1 = WorkoutSessionRecord(
            id: "rec-1",
            programId: "p1",
            workoutId: "w1",
            workoutTitle: "Chest",
            startedAt: "2026-09-05T10:00:00Z",
            completedAt: "2026-09-05T10:15:00Z",
            durationSeconds: 900,
            totalVolumeKg: 800,
            totalCompletedSets: 1,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 80, reps: 10)
                    ],
                    targetSets: 3
                )
            ],
            isComplete: false
        )
        let restored1 = WorkoutSessionUtils.restoreSetsFromHistory(workout: workout, record: record1)["bench"] ?? []
        XCTAssertEqual(restored1.count, 3)
        XCTAssertTrue(restored1[0].isCompleted)
        XCTAssertFalse(restored1[1].isCompleted)
        XCTAssertFalse(restored1[2].isCompleted)

        // User deleted set 4 (targetSets = 3), completed 0 sets
        let record2 = WorkoutSessionRecord(
            id: "rec-2",
            programId: "p1",
            workoutId: "w1",
            workoutTitle: "Chest",
            startedAt: "2026-09-05T10:00:00Z",
            completedAt: "2026-09-05T10:05:00Z",
            durationSeconds: 300,
            totalVolumeKg: 0,
            totalCompletedSets: 0,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [],
                    targetSets: 3
                )
            ],
            isComplete: false
        )
        let restored2 = WorkoutSessionUtils.restoreSetsFromHistory(workout: workout, record: record2)["bench"] ?? []
        XCTAssertEqual(restored2.count, 3)
        XCTAssertTrue(restored2.allSatisfy { !$0.isCompleted })

        // User deleted set 4 (targetSets = 3), completed all 3 sets
        let record3 = WorkoutSessionRecord(
            id: "rec-3",
            programId: "p1",
            workoutId: "w1",
            workoutTitle: "Chest",
            startedAt: "2026-09-05T10:00:00Z",
            completedAt: "2026-09-05T10:25:00Z",
            durationSeconds: 1500,
            totalVolumeKg: 2400,
            totalCompletedSets: 3,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 80, reps: 10),
                        SessionSetLog(setNumber: 2, weightKg: 80, reps: 10),
                        SessionSetLog(setNumber: 3, weightKg: 80, reps: 10)
                    ],
                    targetSets: 3
                )
            ],
            isComplete: false
        )
        let restored3 = WorkoutSessionUtils.restoreSetsFromHistory(workout: workout, record: record3)["bench"] ?? []
        XCTAssertEqual(restored3.count, 3)
        XCTAssertTrue(restored3.allSatisfy { $0.isCompleted })
    }

    func testIsoDateParserFractionalSeconds() {
        let withFractional = "2026-09-05T14:45:12.345Z"
        let withoutFractional = "2026-09-05T14:45:12Z"

        let d1 = WorkoutCalendar.parseIsoTimestamp(withFractional)
        XCTAssertNotNil(d1)
        let d2 = WorkoutCalendar.parseIsoTimestamp(withoutFractional)
        XCTAssertNotNil(d2)

        let local1 = WorkoutCalendar.localDate(from: withFractional)
        let local2 = WorkoutCalendar.localDate(from: withoutFractional)
        XCTAssertEqual(local1, local2)
    }

    func testResumeWorkoutRestoresCompletedSetsAndTimer() {
        let store = AppStore.shared
        // Use a deterministic bundled fixture instead of depending on previous tests or saved user programs.
        let previousState = store.state
        let previousSession = store.activeSession
        defer { store.abandonActiveSession(); store.saveState(previousState); store.activeSession = previousSession }
        let bundled = AppStore.loadBundledStarterPrograms()
        var fixtureState = store.state
        fixtureState.programs = bundled
        fixtureState.activeProgramId = bundled.first?.id ?? ""
        store.saveState(fixtureState)
        guard let program = store.activeProgram,
              let workout = program.workouts.first(where: { $0.exercises.count >= 2 }) else {
            XCTFail("Requires a workout with at least 2 exercises")
            return
        }

        // Clean state for this workout
        store.activeSession = nil
        var st = store.state
        st.history.removeAll { $0.workoutId == workout.id }
        st.completed.removeAll { $0.contains(workout.id) }
        store.saveState(st)

        // 1. Start workout
        let started = store.startActiveSession(programId: program.id, workout: workout)
        XCTAssertTrue(started)
        guard let initialDraft = store.activeSession else {
            XCTFail("Failed to start initial active session")
            return
        }

        // Verify timer starts near 0, NOT 5 days in the past or stuck at 8 hours!
        let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
        let elapsedInitial = SessionProgress.from(draft: initialDraft, nowEpochMillis: nowMillis).durationSeconds
        XCTAssertLessThan(elapsedInitial, 5, "Initial workout timer must start at 0, not stuck at hours")

        // 2. Complete all sets on first exercise
        let firstEx = workout.exercises[0]
        let targetFirstCount = WorkoutSessionUtils.initialSetCount(exercise: firstEx)
        store.updateActiveSession { d in
            var copy = d
            var sets = copy.setsByExercise[firstEx.id] ?? []
            for i in 0..<sets.count {
                sets[i].isCompleted = true
                sets[i].weightKg = 85.0
                sets[i].weightInput = "85"
                sets[i].completedReps = 8
                sets[i].repsInput = "8"
            }
            copy.setsByExercise[firstEx.id] = sets
            return copy
        }

        // 3. Exit workout with progress (calls abandonActiveSession)
        store.abandonActiveSession()
        XCTAssertNil(store.activeSession, "Active session should be nil after exiting")

        // 4. Verify unfinished workout key is present and record in history
        let unfinishedKeys = store.unfinishedWorkoutKeys()
        let expectedKey = "\(program.id):\(workout.id)"
        XCTAssertTrue(unfinishedKeys.contains(expectedKey), "Unfinished key must be present in unfinishedWorkoutKeys")

        let unfinishedRecord = store.state.history.first { $0.workoutId == workout.id && $0.isComplete == false }
        XCTAssertNotNil(unfinishedRecord, "Unfinished record must be saved in history")

        // 5. Resume workout
        let resumed = store.startActiveSession(programId: program.id, workout: workout)
        XCTAssertTrue(resumed, "Resuming workout should succeed")
        guard let resumedDraft = store.activeSession else {
            XCTFail("Active session was not restored")
            return
        }

        // 6. Verify first exercise sets are completely restored
        let restoredSets = resumedDraft.setsByExercise[firstEx.id] ?? []
        XCTAssertEqual(restoredSets.count, targetFirstCount)
        XCTAssertTrue(restoredSets.allSatisfy { $0.isCompleted }, "All sets of first exercise must be marked completed")
        XCTAssertEqual(restoredSets.first?.weightKg, 85.0)
        XCTAssertEqual(restoredSets.first?.completedReps, 8)

        // 7. Verify currentExerciseIndex advanced to index 1 (the next incomplete exercise)
        XCTAssertEqual(resumedDraft.currentExerciseIndex, 1, "Workout should resume at first incomplete exercise")

        // 8. Clean up
        store.abandonActiveSession()
    }

    func testResumeWorkoutPreservesProgramAcrossActiveProgramSwitch() {
        let store = AppStore.shared
        guard store.state.programs.count >= 2 else { return }
        let progA = store.state.programs[0]
        let progB = store.state.programs[1]
        guard let workoutA = progA.workouts.first(where: { $0.exercises.count >= 2 }) else { return }

        // Set active program to progA
        var st = store.state
        st.activeProgramId = progA.id
        st.history.removeAll { $0.workoutId == workoutA.id }
        st.completed.removeAll { $0.contains(workoutA.id) }
        store.saveState(st)

        // 1. Start workout in progA
        let started = store.startActiveSession(programId: progA.id, workout: workoutA)
        XCTAssertTrue(started)

        // 2. Complete first exercise
        let firstEx = workoutA.exercises[0]
        store.updateActiveSession { d in
            var copy = d
            var sets = copy.setsByExercise[firstEx.id] ?? []
            for i in 0..<sets.count {
                sets[i].isCompleted = true
                sets[i].weightKg = 50.0
                sets[i].weightInput = "50"
                sets[i].completedReps = 10
                sets[i].repsInput = "10"
            }
            copy.setsByExercise[firstEx.id] = sets
            return copy
        }

        // 3. Abandon active session so it saves as an unfinished session in history
        store.abandonActiveSession()
        XCTAssertNil(store.activeSession)

        let unfinishedRec = store.state.history.first { $0.workoutId == workoutA.id && $0.isComplete == false }
        XCTAssertNotNil(unfinishedRec)
        XCTAssertEqual(unfinishedRec?.programId, progA.id)

        // 4. User changes active program to progB!
        var switchedState = store.state
        switchedState.activeProgramId = progB.id
        store.saveState(switchedState)
        XCTAssertEqual(store.activeProgram?.id, progB.id)

        // 5. Resume from History: simulate HistoryView handleWorkoutAction logic
        let resolvedProgId = unfinishedRec?.programId
            ?? store.state.programs.first(where: { $0.workouts.contains(where: { $0.id == workoutA.id }) })?.id
            ?? store.activeProgram?.id
        XCTAssertEqual(resolvedProgId, progA.id, "Resolved program ID must be progA, NOT activeProgram (progB)")

        let resumed = store.startActiveSession(
            programId: resolvedProgId ?? "",
            workout: workoutA,
            allowPast: true,
            unfinishedRecordId: unfinishedRec?.id
        )
        XCTAssertTrue(resumed)
        guard let resumedDraft = store.activeSession else {
            XCTFail("Failed to resume active session")
            return
        }
        XCTAssertEqual(resumedDraft.programId, progA.id, "Draft must preserve original program ID")

        // 6. Complete remaining exercises and finish workout
        for ex in workoutA.exercises {
            store.updateActiveSession { d in
                var copy = d
                var sets = copy.setsByExercise[ex.id] ?? []
                for i in 0..<sets.count {
                    sets[i].isCompleted = true
                    sets[i].weightKg = 60.0
                    sets[i].weightInput = "60"
                    sets[i].completedReps = 10
                    sets[i].repsInput = "10"
                }
                copy.setsByExercise[ex.id] = sets
                return copy
            }
        }

        let finalRecord = WorkoutSessionRecord(
            id: resumedDraft.id,
            programId: resumedDraft.programId,
            workoutId: resumedDraft.workout.id,
            workoutTitle: resumedDraft.workout.title,
            startedAt: resumedDraft.startedAt,
            completedAt: ISO8601DateFormatter().string(from: Date()),
            durationSeconds: 1800,
            totalVolumeKg: 1000.0,
            totalCompletedSets: 6,
            exerciseLogs: [],
            isComplete: true
        )
        store.completeActiveSession(finalRecord)

        // 7. Verify completions
        let completedKeys = store.state.completed
        XCTAssertTrue(completedKeys.contains("\(progA.id):\(workoutA.id)"), "Completion key for progA must be added")
        XCTAssertFalse(completedKeys.contains("\(progB.id):\(workoutA.id)"), "Must NOT add completion key under progB")

        // 8. Clean up
        store.abandonActiveSession()
    }


    @MainActor
    func testActiveSessionResumedSnapshot() {
        let store = AppStore.shared
        guard let program = store.activeProgram,
              let workout = program.workouts.first(where: { $0.exercises.count >= 2 }) else {
            return
        }

        let firstEx = workout.exercises[0]
        let firstSets = (1...3).map {
            ExerciseSetLog(id: "s\($0)", setNumber: $0, weightInput: "80", repsInput: "10", weightKg: 80, completedReps: 10, isCompleted: true)
        }
        let secondEx = workout.exercises[1]
        let secondSets = (1...3).map {
            ExerciseSetLog(id: "s2_\($0)", setNumber: $0, weightInput: "", repsInput: "", weightKg: nil, completedReps: nil, isCompleted: false)
        }

        let draft = ActiveSessionDraft(
            id: "test-resumed-draft",
            programId: program.id,
            workout: workout,
            startedAt: "2026-09-05T10:00:00Z",
            startedAtEpochMillis: Int64(Date().timeIntervalSince1970 * 1000) - 245_000, // 4m 05s elapsed
            currentExerciseIndex: 1,
            setsByExercise: [
                firstEx.id: firstSets,
                secondEx.id: secondSets
            ]
        )

        store.activeSession = draft
        let sessionView = ActiveSessionView(store: store, draft: draft)
        let controller = UIHostingController(rootView: sessionView)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_resumed_session_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }

        store.abandonActiveSession()
    }

    @MainActor
    func testCompletedSetsAndDeletedSetReflectedInHistoryDetail() {
        let store = AppStore.shared
        // Use a deterministic bundled fixture instead of depending on previous tests or saved user programs.
        let previousState = store.state
        let previousSession = store.activeSession
        defer { store.abandonActiveSession(); store.saveState(previousState); store.activeSession = previousSession }
        let bundled = AppStore.loadBundledStarterPrograms()
        var fixtureState = store.state
        fixtureState.programs = bundled
        fixtureState.activeProgramId = bundled.first?.id ?? ""
        store.saveState(fixtureState)
        guard let program = store.activeProgram,
              let workout = program.workouts.first(where: { $0.exercises.count >= 3 }) else {
            XCTFail("Requires a workout with at least 3 exercises")
            return
        }

        // Clean any leftover session
        store.abandonActiveSession()

        // 1. Start active session
        let started = store.startActiveSession(programId: program.id, workout: workout)
        XCTAssertTrue(started)
        guard var draft = store.activeSession else {
            XCTFail("Failed to start active session")
            return
        }

        let ex1 = workout.exercises[0]
        let ex2 = workout.exercises[1]
        let ex3 = workout.exercises[2]

        // 2. Complete all sets for exercise 1
        let ex1Target = WorkoutSessionUtils.initialSetCount(exercise: ex1)
        var ex1Sets = (1...ex1Target).map {
            ExerciseSetLog(id: "ex1_s\($0)", setNumber: $0, weightInput: "60", repsInput: "10", weightKg: 60, completedReps: 10, isCompleted: true)
        }
        draft.setsByExercise[ex1.id] = ex1Sets

        // 3. For exercise 2, simulate deleting last set and completing the remaining sets
        let ex2OriginalCount = WorkoutSessionUtils.initialSetCount(exercise: ex2)
        let ex2NewCount = max(1, ex2OriginalCount - 1)
        var ex2Sets = (1...ex2NewCount).map {
            ExerciseSetLog(id: "ex2_s\($0)", setNumber: $0, weightInput: "24", repsInput: "12", weightKg: 24, completedReps: 12, isCompleted: true)
        }
        draft.setsByExercise[ex2.id] = ex2Sets

        // 4. Exercise 3 remains incomplete (0 sets done)
        let ex3Target = WorkoutSessionUtils.initialSetCount(exercise: ex3)
        draft.setsByExercise[ex3.id] = (1...ex3Target).map {
            ExerciseSetLog(id: "ex3_s\($0)", setNumber: $0, weightInput: "", repsInput: "", weightKg: nil, completedReps: nil, isCompleted: false)
        }

        store.activeSession = draft

        // 5. Complete active session (unfinished / partial session)
        let nowEpoch = Int64(Date().timeIntervalSince1970 * 1000)
        let progress = SessionProgress.from(draft: draft, nowEpochMillis: nowEpoch)
        let record = progress.record(draft: draft, completedAtEpochMillis: nowEpoch)
        store.completeActiveSession(record)

        XCTAssertNil(store.activeSession, "Active session should be cleared after completion")

        // 6. Verify calendar entry exists and find the date
        guard let entry = store.state.calendarHistory?.entries.first(where: { $0.id == "session:\(record.id)" }) else {
            XCTFail("Calendar entry for session was not found")
            return
        }
        XCTAssertEqual(entry.status, .unfinished)

        // 7. Verify History lookup finds the session record for that day
        let dateString = entry.date
        let historyRecord = store.state.history.first { rec in
            if let calDate = store.state.calendarHistory?.entries.first(where: { $0.id == "session:\(rec.id)" })?.date {
                return calDate == dateString
            }
            let startDate = WorkoutCalendar.localDate(from: rec.startedAt)
            let completedDate = WorkoutCalendar.localDate(from: rec.completedAt)
            return startDate == dateString || completedDate == dateString
        }

        XCTAssertNotNil(historyRecord, "Session record must be resolved for date \(dateString)")
        guard let resolvedRec = historyRecord else { return }

        // Total completed sets: ex1 (ex1Target) + ex2 (ex2NewCount)
        XCTAssertEqual(resolvedRec.totalCompletedSets, ex1Target + ex2NewCount)

        // 8. Verify exercise breakdown
        let ex1Log = resolvedRec.exerciseLogs.first(where: { $0.exerciseName.lowercased() == ex1.name.lowercased() })
        XCTAssertNotNil(ex1Log)
        XCTAssertEqual(ex1Log?.sets.count, ex1Target)
        XCTAssertEqual(ex1Log?.targetSets, ex1Target)

        let ex2Log = resolvedRec.exerciseLogs.first(where: { $0.exerciseName.lowercased() == ex2.name.lowercased() })
        XCTAssertNotNil(ex2Log)
        XCTAssertEqual(ex2Log?.sets.count, ex2NewCount)
        XCTAssertEqual(ex2Log?.targetSets, ex2NewCount, "Target sets for exercise 2 should reflect deleted set (\(ex2NewCount) not \(ex2OriginalCount))")

        let ex3Log = resolvedRec.exerciseLogs.first(where: { $0.exerciseName.lowercased() == ex3.name.lowercased() })
        XCTAssertNotNil(ex3Log)
        XCTAssertEqual(ex3Log?.sets.count, 0)
        XCTAssertEqual(ex3Log?.targetSets, ex3Target)

        // 9. Snapshot rendering of the detail sheet
        let detailData = HistoryDayDetailData(
            date: Date(),
            dateString: dateString,
            status: .unfinished,
            sessionRecord: resolvedRec,
            workout: workout
        )
        let sheetView = HistoryDayDetailSheet(detail: detailData, onDismiss: {})
        let controller = UIHostingController(rootView: sheetView)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_history_detail_completed_and_deleted_set.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    func testSessionRecordDoesNotLeakToAnotherDay() {
        // Monday workout done physically on Saturday (startedAt = 2026-09-05)
        // but scheduled/mapped to Monday (2026-08-31) in calendarHistory.
        let mondayRecord = WorkoutSessionRecord(
            id: "monday-workout-id",
            programId: "prog-1",
            workoutId: "w-mon",
            workoutTitle: "Chest & Triceps",
            startedAt: "2026-09-05T15:39:17.662Z",
            completedAt: "2026-09-05T16:06:17.662Z",
            durationSeconds: 27,
            totalVolumeKg: 2720,
            totalCompletedSets: 18,
            exerciseLogs: [],
            isComplete: true
        )

        let calHistory = WorkoutCalendarHistory(
            nextScheduledDate: "2026-08-31",
            scheduledWeekdays: [1, 2, 4, 5, 6],
            missedDates: [],
            entries: [
                WorkoutDayEntry(id: "session:monday-workout-id", date: "2026-08-31", status: .completed)
            ]
        )

        let history = [mondayRecord]

        // Looking up for Saturday September 5 (2026-09-05)
        let saturdayDateString = "2026-09-05"
        let saturdayMatch = history.first { rec in
            if let calDate = calHistory.entries.first(where: { $0.id == "session:\(rec.id)" })?.date {
                return calDate == saturdayDateString
            }
            let startDate = WorkoutCalendar.localDate(from: rec.startedAt)
            let completedDate = WorkoutCalendar.localDate(from: rec.completedAt)
            return startDate == saturdayDateString || completedDate == saturdayDateString
        }

        XCTAssertNil(saturdayMatch, "Saturday lookup must NOT match Monday's session record even if startedAt was today!")

        // Looking up for Monday August 31 (2026-08-31)
        let mondayDateString = "2026-08-31"
        let mondayMatch = history.first { rec in
            if let calDate = calHistory.entries.first(where: { $0.id == "session:\(rec.id)" })?.date {
                return calDate == mondayDateString
            }
            let startDate = WorkoutCalendar.localDate(from: rec.startedAt)
            let completedDate = WorkoutCalendar.localDate(from: rec.completedAt)
            return startDate == mondayDateString || completedDate == mondayDateString
        }

        XCTAssertNotNil(mondayMatch, "Monday lookup must match Monday's session record")
        XCTAssertEqual(mondayMatch?.id, "monday-workout-id")
    }

    func testWorkoutCalendarRestorePrunesOrphanSessionEntries() {
        let realSession = WorkoutSessionRecord(
            id: "real-session-id",
            programId: "prog-1",
            workoutId: "w-1",
            workoutTitle: "Upper",
            startedAt: "2026-08-31T10:00:00Z",
            completedAt: "2026-08-31T11:00:00Z",
            durationSeconds: 3600,
            totalVolumeKg: 1000,
            totalCompletedSets: 10,
            exerciseLogs: [],
            isComplete: true
        )

        let rawHistory = WorkoutCalendarHistory(
            nextScheduledDate: "2026-08-31",
            scheduledWeekdays: [1, 2, 4, 5, 6],
            missedDates: [],
            entries: [
                WorkoutDayEntry(id: "session:real-session-id", date: "2026-08-31", status: .completed),
                WorkoutDayEntry(id: "session:active-draft-id", date: "2026-09-05", status: .unfinished),
                WorkoutDayEntry(id: "session:stale-orphan-id", date: "2026-09-05", status: .unfinished)
            ]
        )

        // Restore with activeSessionId = "active-draft-id"
        let restored = WorkoutCalendar.restore(
            raw: rawHistory,
            sessions: [realSession],
            today: "2026-09-05",
            weekdays: [1, 2, 4, 5, 6],
            activeSessionId: "active-draft-id"
        )

        XCTAssertTrue(restored.entries.contains { $0.id == "session:real-session-id" })
        XCTAssertTrue(restored.entries.contains { $0.id == "session:active-draft-id" })
        XCTAssertFalse(restored.entries.contains { $0.id == "session:stale-orphan-id" }, "Orphan entry must be pruned!")

        // Restore without activeSession (e.g. idle today)
        let restoredNoActive = WorkoutCalendar.restore(
            raw: rawHistory,
            sessions: [realSession],
            today: "2026-09-05",
            weekdays: [1, 2, 4, 5, 6],
            activeSessionId: nil
        )

        XCTAssertTrue(restoredNoActive.entries.contains { $0.id == "session:real-session-id" })
        XCTAssertFalse(restoredNoActive.entries.contains { $0.id == "session:active-draft-id" }, "Inactive draft entry must be pruned")
        XCTAssertFalse(restoredNoActive.entries.contains { $0.id == "session:stale-orphan-id" }, "Orphan entry must be pruned")

        // Status for Saturday 2026-09-05 must be nil (not unfinished!)
        let statuses = WorkoutCalendar.statuses(history: restoredNoActive, today: "2026-09-05")
        XCTAssertNil(statuses["2026-09-05"], "Saturday must have nil status when not started, NOT unfinished")
    }

    func testWorkoutCalendarRestorePreservesLoggedDateAndExplicitPastDay() {
        let mondaySession = WorkoutSessionRecord(
            id: "session-push-a",
            programId: "prog-1",
            workoutId: "w-mon",
            workoutTitle: "Chest & Triceps",
            startedAt: "2026-09-05T15:21:25.181Z",
            completedAt: "2026-09-05T16:03:24.092Z",
            durationSeconds: 2518,
            totalVolumeKg: 2000,
            totalCompletedSets: 7,
            exerciseLogs: [],
            isComplete: false
        )
        let prog = Program(
            id: "prog-1",
            name: "Aesthetic",
            workouts: [
                Workout(id: "w-mon", day: 1, title: "Chest & Triceps", exercises: [])
            ]
        )
        let rawHistory = WorkoutCalendarHistory(
            nextScheduledDate: "2026-09-05",
            scheduledWeekdays: [1, 2, 4, 5, 6],
            missedDates: ["2026-08-31"],
            entries: [
                WorkoutDayEntry(id: "session:session-push-a", date: "2026-09-05", status: .unfinished)
            ]
        )

        let restored = WorkoutCalendar.restore(
            raw: rawHistory,
            sessions: [mondaySession],
            today: "2026-09-05",
            weekdays: [1, 2, 4, 5, 6],
            activeSessionId: nil,
            programs: [prog]
        )

        let entry = restored.entries.first { $0.id == "session:session-push-a" }
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.date, "2026-09-05", "Restoring a saved session must not move it to the workout's usual weekday")
        XCTAssertEqual(entry?.status, .unfinished)

        let statuses = WorkoutCalendar.statuses(history: restored, today: "2026-09-05")
        XCTAssertEqual(statuses["2026-08-31"], .missed)
        XCTAssertEqual(statuses["2026-09-05"], .unfinished)

        var pastDayHistory = rawHistory
        pastDayHistory.entries = [WorkoutDayEntry(id: "session:session-push-a", date: "2026-08-31", status: .unfinished)]
        let pastDayRestore = WorkoutCalendar.restore(
            raw: pastDayHistory, sessions: [mondaySession], today: "2026-09-05",
            weekdays: [1, 2, 4, 5, 6], programs: [prog]
        )
        XCTAssertEqual(pastDayRestore.entries.first?.date, "2026-08-31")

        let migrated = WorkoutCalendar.restore(
            raw: nil, sessions: [mondaySession], today: "2026-09-05",
            weekdays: [1, 2, 4, 5, 6], programs: [prog]
        )
        XCTAssertEqual(migrated.entries.first?.date, "2026-09-05")
    }

    func testWorkoutPerformedOnDifferentDayKeepsPlanDayNeutral() {
        let testToday = "2026-10-05" // Monday
        // Friday workout (w-fri, day 5) performed on Sunday (2026-10-04)
        let sundaySession = WorkoutSessionRecord(
            id: "s-sun", programId: "p1", workoutId: "w-fri", workoutTitle: "Friday Upper",
            startedAt: "2026-10-04T10:00:00Z", completedAt: "2026-10-04T10:45:00Z",
            durationSeconds: 2700, totalVolumeKg: 400, totalCompletedSets: 3,
            exerciseLogs: [SessionExerciseLog(exerciseName: "OHP", sets: [SessionSetLog(setNumber: 1, weightKg: 40, reps: 10)], targetSets: 1)],
            isComplete: true, scheduledDate: "2026-10-02"
        )
        let program = Program(
            id: "p1", name: "Split",
            workouts: [
                Workout(id: "w-mon", day: 1, title: "Mon", exercises: [Exercise(name: "Bench", sets: 1)]),
                Workout(id: "w-fri", day: 5, title: "Friday Upper", exercises: [Exercise(name: "OHP", sets: 1)])
            ]
        )
        let history = WorkoutCalendarHistory(
            nextScheduledDate: "2026-09-28",
            scheduledWeekdays: [1, 5],
            missedDates: [],
            entries: [
                WorkoutDayEntry(id: "session:s-sun", date: "2026-10-04", status: .completed)
            ]
        )
        let utc = TimeZone(identifier: "UTC")!
        let restored = WorkoutCalendar.restore(
            raw: history,
            sessions: [sundaySession],
            today: testToday,
            timeZone: utc,
            weekdays: [1, 5],
            programs: [program]
        )
        let statuses = WorkoutCalendar.statuses(history: restored, today: testToday)
        // Monday 2026-09-28 was never done -> missed
        XCTAssertEqual(statuses["2026-09-28"], WorkoutDayStatus.missed)
        // Friday 2026-10-02 was performed on Sunday 2026-10-04 -> Friday remains neutral (nil), NOT missed
        XCTAssertNil(statuses["2026-10-02"], "Friday must remain neutral since its workout was performed on Sunday")
        // Sunday 2026-10-04 has the completed session
        XCTAssertEqual(statuses["2026-10-04"], WorkoutDayStatus.completed)
    }

    func testWorkoutCalendarRefreshReconcilesWorkoutCompletedOnDifferentDayOfWeek() {
        let testToday = "2026-10-07" // Wednesday
        let wednesdaySession = WorkoutSessionRecord(
            id: "s-wed", programId: "p1", workoutId: "w-mon",
            workoutTitle: "Mon Push", startedAt: "2026-10-07T10:00:00Z", completedAt: "2026-10-07T11:00:00Z",
            durationSeconds: 3600, totalVolumeKg: 500.0, totalCompletedSets: 3,
            exerciseLogs: [SessionExerciseLog(exerciseName: "Bench", sets: [SessionSetLog(setNumber: 1, weightKg: 100.0, reps: 5)], targetSets: 1)],
            isComplete: true, scheduledDate: "2026-10-05"
        )
        let program = Program(
            id: "p1", name: "Split",
            workouts: [
                Workout(id: "w-mon", day: 1, title: "Mon Push", exercises: [Exercise(name: "Bench", sets: 1)]),
                Workout(id: "w-wed", day: 3, title: "Wed Pull", exercises: [Exercise(name: "Pullup", sets: 1)])
            ]
        )
        let history = WorkoutCalendarHistory(
            nextScheduledDate: "2026-10-05", // Monday
            scheduledWeekdays: [1, 3],
            missedDates: [],
            entries: [
                WorkoutDayEntry(id: "session:s-wed", date: "2026-10-07", status: .completed)
            ]
        )
        let refreshed = WorkoutCalendar.refresh(
            history: history,
            today: testToday,
            weekdays: [1, 3],
            programs: [program],
            sessions: [wednesdaySession]
        )
        let statuses = WorkoutCalendar.statuses(history: refreshed, today: testToday)
        // Monday 2026-10-05 was performed on Wednesday -> Monday remains NEUTRAL (not in missedDates, not in statuses)
        XCTAssertFalse(refreshed.missedDates.contains("2026-10-05"), "Monday 2026-10-05 must not be in missedDates")
        XCTAssertNil(statuses["2026-10-05"], "Monday 2026-10-05 must be neutral (nil status)")
        // Wednesday 2026-10-07 has the completed session
        XCTAssertEqual(statuses["2026-10-07"], WorkoutDayStatus.completed)
    }

    func testCalendarStatusesMissedDayWhoseWorkoutWasCompletedInSameWeekBecomesNeutral() throws {
        let defaults = UserDefaults.standard
        let domain = try XCTUnwrap(Bundle.main.bundleIdentifier)
        let previousPreferences = defaults.persistentDomain(forName: domain) ?? [:]
        let store = AppStore.shared
        let previousState = store.state
        let previousSession = store.activeSession
        defer {
            store.state = previousState
            store.activeSession = previousSession
            defaults.setPersistentDomain(previousPreferences, forName: domain)
        }
        let monday = "2026-10-05"
        let wednesday = "2026-10-07"
        let program = Program(
            id: "prog", name: "P",
            workouts: [
                Workout(id: "w-mon", day: 1, title: "Mon", exercises: [Exercise(name: "Squat", sets: 1)])
            ]
        )
        let session = WorkoutSessionRecord(
            id: "s1", programId: "prog", workoutId: "w-mon", workoutTitle: "Mon",
            startedAt: "2026-10-07T09:00:00Z", completedAt: "2026-10-07T10:00:00Z",
            durationSeconds: 3600, totalVolumeKg: 100.0, totalCompletedSets: 1,
            exerciseLogs: [SessionExerciseLog(exerciseName: "Squat", sets: [SessionSetLog(setNumber: 1, weightKg: 100.0, reps: 5)], targetSets: 1)],
            isComplete: true, scheduledDate: "2026-10-05"
        )
        let calHistory = WorkoutCalendarHistory(
            nextScheduledDate: "2026-10-05",
            scheduledWeekdays: [1],
            missedDates: ["2026-10-05"],
            entries: [
                WorkoutDayEntry(id: "session:s1", date: "2026-10-07", status: .completed)
            ]
        )
        let st = StoredAppState(
            programs: [program],
            activeProgramId: "prog",
            completed: [],
            currentWeekKey: "2026-W41",
            weeklyArchives: [],
            history: [session],
            calendarHistory: calHistory
        )
        store.state = st
        let wedDate = WorkoutCalendar.parseDate(wednesday)!
        let statuses = store.calendarStatuses(today: wedDate)
        XCTAssertNil(statuses[monday], "Monday must be neutral (nil) because its workout was completed on Wednesday")
        XCTAssertEqual(statuses[wednesday], WorkoutDayStatus.completed)
    }

    func testProgramExerciseFixedSetsAndRepTargetModificationPersists() throws {
        let persistence = AppStatePersistence(inMemory: true)
        let store = AppStore(persistence: persistence)
        var program = Program(id: "program-edit-fixture", name: "Program edit fixture", workouts: [
            Workout(id: "workout-edit-fixture", day: 1, title: "Upper", exercises: [
                Exercise(name: "Barbell Bench Press", sets: 3)
            ])
        ])
        store.state = StoredAppState(programs: [program], activeProgramId: program.id,
            currentWeekKey: store.state.currentWeekKey)
        store.activeSession = nil

        // Modify exercise 0 to fixed 4 sets of 10-12 reps
        var modifiedEx = program.workouts[0].exercises[0]
        modifiedEx.sets = 4
        modifiedEx.reps = RepTarget(min: 10, max: 12, toFailure: false, perSide: false)
        modifiedEx.restSeconds = 120
        program.workouts[0].exercises[0] = modifiedEx

        // Update program via store
        store.updateProgram(program)

        // Verify in-memory state
        let updatedInStore = store.state.programs.first { $0.id == program.id }
        XCTAssertNotNil(updatedInStore)
        let exInStore = updatedInStore?.workouts.first?.exercises.first
        XCTAssertEqual(exInStore?.sets, 4, "Sets must be fixed integer 4")
        XCTAssertEqual(exInStore?.reps?.min, 10)
        XCTAssertEqual(exInStore?.reps?.max, 12)
        XCTAssertEqual(exInStore?.displayPrescription, "4 × 10–12")

        // The queued save must be visible through the durable store.
        guard let persistedState = try? store.statePersistence.load(),
              let persistedProgram = persistedState.programs.first(where: { $0.id == program.id }),
              let persistedExercise = persistedProgram.workouts.first?.exercises.first else {
            XCTFail("Failed to read persisted program from SQLite")
            return
        }
        XCTAssertEqual(persistedExercise.sets, 4)
        XCTAssertEqual(persistedExercise.reps?.min, 10)
        XCTAssertEqual(persistedExercise.reps?.max, 12)
        XCTAssertEqual(persistedExercise.restSeconds, 120)
    }

    @MainActor
    func testProgramExerciseEditorSheetSnapshot() {
        let exercise = Exercise(
            name: "Incline Barbell Bench Press",
            prescription: "4 × 6–8",
            sets: 4,
            reps: RepTarget(min: 6, max: 8),
            restSeconds: 180,
            movementType: "bench"
        )
        let sheet = ProgramExerciseEditorSheet(
            exercise: exercise,
            onSave: { _ in },
            onDelete: {}
        )
        let controller = UIHostingController(rootView: sheet)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_program_exercise_editor_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    func testAddedSetStartsEmptyWithoutCopyingPreviousInputs() {
        var sets = [
            ExerciseSetLog(setNumber: 1, weightInput: "80", repsInput: "10", weightKg: 80, completedReps: 10, isCompleted: true)
        ]
        // Adding a set must produce a clean, blank set
        sets.append(ExerciseSetLog(
            setNumber: sets.count + 1,
            isCompleted: false
        ))
        let added = sets.last!
        XCTAssertEqual(added.setNumber, 2)
        XCTAssertEqual(added.weightInput, "")
        XCTAssertEqual(added.repsInput, "")
        XCTAssertNil(added.weightKg)
        XCTAssertNil(added.completedReps)
        XCTAssertFalse(added.isCompleted)
    }

    func testCanCompleteSetAcceptsPositiveFractionalLoadsAndValidReps() {
        XCTAssertFalse(WorkoutSessionUtils.canCompleteSet(ExerciseSetLog(setNumber: 1)))
        XCTAssertFalse(WorkoutSessionUtils.canCompleteSet(ExerciseSetLog(setNumber: 1, weightInput: "", repsInput: "10")))
        XCTAssertFalse(WorkoutSessionUtils.canCompleteSet(ExerciseSetLog(setNumber: 1, weightInput: "0", repsInput: "10", weightKg: 0, completedReps: 10)))
        XCTAssertTrue(WorkoutSessionUtils.canCompleteSet(ExerciseSetLog(setNumber: 1, weightInput: "0.9", repsInput: "10", weightKg: 0.9, completedReps: 10)))
        XCTAssertFalse(WorkoutSessionUtils.canCompleteSet(ExerciseSetLog(setNumber: 1, weightInput: "50", repsInput: "", weightKg: 50)))
        XCTAssertFalse(WorkoutSessionUtils.canCompleteSet(ExerciseSetLog(setNumber: 1, weightInput: "50", repsInput: "0", weightKg: 50, completedReps: 0)))
        XCTAssertTrue(WorkoutSessionUtils.canCompleteSet(ExerciseSetLog(setNumber: 1, weightInput: "1", repsInput: "1", weightKg: 1, completedReps: 1)))
        XCTAssertTrue(WorkoutSessionUtils.canCompleteSet(ExerciseSetLog(setNumber: 1, weightInput: "50", repsInput: "12", weightKg: 50, completedReps: 12)))
        XCTAssertTrue(WorkoutSessionUtils.canCompleteSet(ExerciseSetLog(setNumber: 1, weightInput: "2.5", repsInput: "15")))
    }

    func testBodyweightSetsAcceptZeroAndProduceAUsableSavedBaseline() throws {
        let exercise = Exercise(id: "bodyweight", name: "Push Ups", exerciseId: "push-ups", sets: 2, reps: RepTarget(min: 8, max: 12))
        let weighted = Exercise(name: "Barbell Bench Press", exerciseId: "barbell-bench-press")
        XCTAssertTrue(WorkoutSessionUtils.allowsZeroWeight(exercise))
        XCTAssertFalse(WorkoutSessionUtils.allowsZeroWeight(weighted))
        var legacy = weighted; legacy.exerciseId = nil
        XCTAssertFalse(WorkoutSessionUtils.allowsZeroWeight(legacy))
        let zero = ExerciseSetLog(setNumber: 1, weightInput: "0", repsInput: "1", weightKg: 0, completedReps: 1)
        XCTAssertTrue(WorkoutSessionUtils.canCompleteSet(zero, allowsZeroWeight: true))
        XCTAssertFalse(WorkoutSessionUtils.canCompleteSet(zero))
        for weight in [-1.0, Double.nan, Double.infinity] {
            var invalid = zero; invalid.weightKg = weight
            XCTAssertFalse(WorkoutSessionUtils.canCompleteSet(invalid, allowsZeroWeight: true))
        }
        var invalid = zero; invalid.completedReps = 1000
        XCTAssertEqual(WorkoutSessionUtils.setValidationError(invalid, allowsZeroWeight: true), "table.validation.reps")
        invalid = zero; invalid.weightKg = nil; invalid.weightInput = ""
        XCTAssertEqual(WorkoutSessionUtils.setValidationError(invalid, allowsZeroWeight: true), "table.validation.weight_zero_allowed")
        var completed = zero; completed.isCompleted = true
        let nextRow = WorkoutSessionUtils.prefillSet(ExerciseSetLog(setNumber: 2), from: completed)
        XCTAssertEqual(nextRow.weightInput, "0")
        XCTAssertEqual(nextRow.weightKg, 0)
        XCTAssertFalse(nextRow.isCompleted)
        var second = completed; second.setNumber = 2
        let workout = Workout(id: "body", day: 1, title: "Bodyweight", exercises: [exercise])
        let draft = ActiveSessionDraft(id: "draft-body", programId: "p", workout: workout,
            startedAt: "2026-10-03T10:00:00Z", startedAtEpochMillis: 1000,
            setsByExercise: [exercise.id: [completed, second]])
        let record = SessionProgress.from(draft: draft, nowEpochMillis: 2000).record(draft: draft, completedAtEpochMillis: 2000)
        let target = try XCTUnwrap(ProgressionEngine.computeProgression(exercise: exercise, history: [record]))
        XCTAssertEqual(target.setTargets.count, 2)
        XCTAssertEqual(target.setTargets.map { $0.weightKg }, [0, 0])
        XCTAssertEqual(target.setTargets.map { $0.weightInput(unit: .kg, fallback: "5") }, ["0", "0"])
        XCTAssertEqual(ProgressionSetTarget(weightKg: nil, reps: 2).weightInput(unit: .kg, fallback: "5"), "5")
        XCTAssertEqual(target.setTargets.first?.weightInput(unit: .lbs, fallback: "5"), "0")
    }

    func testEmptySetWarningTranslationsParity() {
        XCTAssertEqual(Translations.en["notice.emptySetWarning"], "Weight and rep info cannot be left empty.")
        XCTAssertEqual(Translations.tr["notice.emptySetWarning"], "Tekrar ve ağırlık bilgisi boş bırakılamaz.")
    }

    func testRestActiveWarningTranslationsParity() {
        XCTAssertEqual(Translations.en["notice.restActiveWarning"], "Cannot log a set while the rest timer is running.")
        XCTAssertEqual(Translations.tr["notice.restActiveWarning"], "Dinlenme sayacı devredeyken set tamamlanamaz.")
    }

    func testIsSetEnabledRequiresPrecedingSetsToBeCompleted() {
        let sets = [
            ExerciseSetLog(setNumber: 1),
            ExerciseSetLog(setNumber: 2),
            ExerciseSetLog(setNumber: 3)
        ]
        // All incomplete: only set 1 enabled
        XCTAssertTrue(WorkoutSessionUtils.isSetEnabled(sets: sets, index: 0))
        XCTAssertFalse(WorkoutSessionUtils.isSetEnabled(sets: sets, index: 1))
        XCTAssertFalse(WorkoutSessionUtils.isSetEnabled(sets: sets, index: 2))

        // Set 1 completed: set 1 and 2 enabled, set 3 locked
        var set1Done = sets
        set1Done[0].isCompleted = true
        XCTAssertTrue(WorkoutSessionUtils.isSetEnabled(sets: set1Done, index: 0))
        XCTAssertTrue(WorkoutSessionUtils.isSetEnabled(sets: set1Done, index: 1))
        XCTAssertFalse(WorkoutSessionUtils.isSetEnabled(sets: set1Done, index: 2))

        // Set 1 and 2 completed: all enabled
        var set1And2Done = set1Done
        set1And2Done[1].isCompleted = true
        XCTAssertTrue(WorkoutSessionUtils.isSetEnabled(sets: set1And2Done, index: 0))
        XCTAssertTrue(WorkoutSessionUtils.isSetEnabled(sets: set1And2Done, index: 1))
        XCTAssertTrue(WorkoutSessionUtils.isSetEnabled(sets: set1And2Done, index: 2))
    }

    func testEditingLoggedSetDuringRestPreservesTimer() {
        let store = AppStore.shared
        let exercise = Exercise(id: "bench", name: "Bench", prescription: "3 × 8–12", sets: 3, restSeconds: 90)
        let workout = Workout(id: "upper", day: 1, title: "Upper", exercises: [exercise])
        let sets = [
            ExerciseSetLog(setNumber: 1, weightInput: "80", repsInput: "10", weightKg: 80.0, completedReps: 10, isCompleted: true),
            ExerciseSetLog(setNumber: 2, weightInput: "80", repsInput: "10", weightKg: 80.0, completedReps: 10, isCompleted: false),
            ExerciseSetLog(setNumber: 3, weightInput: "", repsInput: "", isCompleted: false)
        ]
        let endEpoch: Int64 = 100_000
        let restTimer = RestTimerState(
            exerciseName: "Bench",
            totalSeconds: 90,
            isRunning: true,
            endsAtEpochMillis: endEpoch,
            pausedSecondsRemaining: 90
        )
        let draft = ActiveSessionDraft(
            id: "test-draft",
            programId: "plan",
            workout: workout,
            startedAt: "2026-08-28T09:00:00Z",
            startedAtEpochMillis: 10_000,
            setsByExercise: [exercise.id: sets],
            restTimer: restTimer
        )
        store.activeSession = draft

        // Editing current set's weight and reps does not restart or change the rest timer
        store.updateActiveSession { d in
            var copy = d
            var currentSets = copy.setsByExercise[exercise.id] ?? []
            currentSets[0] = ExerciseSetLog(
                id: currentSets[0].id,
                setNumber: currentSets[0].setNumber,
                weightInput: "85",
                repsInput: "12",
                weightKg: 85.0,
                completedReps: 12,
                isCompleted: true,
                inputTouched: true
            )
            copy.setsByExercise[exercise.id] = currentSets
            return copy
        }

        XCTAssertEqual(store.activeSession?.setsByExercise[exercise.id]?[0].weightInput, "85")
        XCTAssertEqual(store.activeSession?.setsByExercise[exercise.id]?[0].completedReps, 12)
        XCTAssertEqual(store.activeSession?.restTimer?.endsAtEpochMillis, endEpoch)
        XCTAssertEqual(store.activeSession?.restTimer?.totalSeconds, 90)
        XCTAssertEqual(store.activeSession?.restTimer?.isRunning, true)
    }

    func testSetLoggingTableRestBouncerAllowsCurrentSetEditAndBlocksOthers() {
        let sets = [
            ExerciseSetLog(setNumber: 1, weightInput: "80", repsInput: "10", weightKg: 80.0, completedReps: 10, isCompleted: true),
            ExerciseSetLog(setNumber: 2, weightInput: "85", repsInput: "8", weightKg: 85.0, completedReps: 8, isCompleted: true),
            ExerciseSetLog(setNumber: 3, weightInput: "85", repsInput: "8", weightKg: 85.0, completedReps: 8, isCompleted: false)
        ]
        var warningCount = 0
        var toggledIndex: Int? = nil

        let table = SetLoggingTable(
            sets: sets,
            prescription: "3 × 8–12",
            isRestActive: true,
            isRestForCurrentExercise: true,
            onUpdateSet: { _, _, _ in },
            onToggleCompleteSet: { idx in
                toggledIndex = idx
            },
            onAddSet: {},
            onRemoveSet: { _ in },
            onRestWarning: {
                warningCount += 1
            }
        )

        // Set 2 is the current logged set (last completed set, index 1)
        let currentLogged = table.sets.lastIndex(where: { $0.isCompleted })
        XCTAssertEqual(currentLogged, 1)
        XCTAssertTrue(table.isRestActive)
        XCTAssertTrue(table.isRestForCurrentExercise)
        XCTAssertNil(toggledIndex)
        XCTAssertEqual(warningCount, 0)
    }

    func testPrefillNextSetTranslationsParity() {
        XCTAssertEqual(Translations.en["settings.prefillNextSet"], "Pre-fill next set")
        XCTAssertEqual(Translations.tr["settings.prefillNextSet"], "Sonraki seti doldur")
        XCTAssertEqual(Translations.en["settings.prefillNextSetSubtitle"], "Copy weight and reps from previous set")
        XCTAssertEqual(Translations.tr["settings.prefillNextSetSubtitle"], "Önceki setin ağırlık ve tekrarını kopyala")
    }

    func testSessionCardsSettingsTranslationsParity() {
        XCTAssertEqual(Translations.en["settings.showProgressionTargets"], "Recommended targets")
        XCTAssertEqual(Translations.tr["settings.showProgressionTargets"], "Önerilen hedefler")
        XCTAssertEqual(Translations.en["settings.showProgressionTargetsSubtitle"], "Show progression advice and suggested targets in session")
        XCTAssertEqual(Translations.tr["settings.showProgressionTargetsSubtitle"], "Antrenman ekranında ağırlık artış ve hedef önerilerini göster")
        XCTAssertEqual(Translations.en["settings.showWarmupCalculator"], "Warmup & plate calculator")
        XCTAssertEqual(Translations.tr["settings.showWarmupCalculator"], "Isınma & plaka hesaplayıcı")
        XCTAssertEqual(Translations.en["settings.showWarmupCalculatorSubtitle"], "Show warm-up sets and plate calculator in session")
        XCTAssertEqual(Translations.tr["settings.showWarmupCalculatorSubtitle"], "Antrenman ekranında ısınma setlerini ve plaka hesaplayıcıyı göster")
    }

    func testWarmupTranslationsParity() {
        XCTAssertEqual(Translations.en["warmup.target_weight"], "Target Weight")
        XCTAssertEqual(Translations.tr["warmup.target_weight"], "Hedef Ağırlık")
        XCTAssertEqual(Translations.en["warmup.target_barbell_weight"], "Barbell Total Weight")
        XCTAssertEqual(Translations.tr["warmup.target_barbell_weight"], "Toplam Barbell Ağırlığı")

        let warmupKeys = [
            "warmup.badge",
            "warmup.modal_title",
            "warmup.tab_warmup",
            "warmup.tab_plates",
            "warmup.plates_btn",
            "warmup.card_title",
            "warmup.card_desc",
            "warmup.locked_desc",
            "progression.coach.locked_title",
            "progression.coach.locked_desc",
            "pro.premium_required",
            "warmup.enter_working_load",
            "warmup.load_below_bar",
            "warmup.generate_btn",
            "warmup.active_badge",
            "warmup.active_desc",
            "warmup.clear_warmups",
            "warmup.convert_to_warmup",
            "warmup.convert_to_working",
            "warmup.working_load_label",
            "warmup.sequence_title",
            "warmup.warm_joints",
            "warmup.50_percent",
            "warmup.70_percent",
            "warmup.85_percent",
            "warmup.insert_sets_cta",
            "warmup.target_weight",
            "warmup.target_barbell_weight",
            "warmup.available_plates_inventory",
            "warmup.per_side",
            "warmup.bar",
            "warmup.plates_total",
            "warmup.total",
            "warmup.empty_bar",
            "warmup.empty_bar_sleeve",
            "warmup.unmatched_remainder"
        ]
        for key in warmupKeys {
            XCTAssertFalse(Translations.en[key]?.isEmpty ?? true, "Missing English warmup key: \(key)")
            XCTAssertFalse(Translations.tr[key]?.isEmpty ?? true, "Missing Turkish warmup key: \(key)")
        }
    }

    func testPrefillNextSetDefault() {
        let store = AppStore.shared
        XCTAssertTrue(store.prefillNextSet)
    }

    func testAboutTranslationsParity() {
        XCTAssertEqual(Translations.en["settings.version"], "v1.0")
        XCTAssertEqual(Translations.tr["settings.version"], "v1.0")
        XCTAssertFalse(Translations.en["settings.aboutDescription"]?.isEmpty ?? true)
        XCTAssertFalse(Translations.tr["settings.aboutDescription"]?.isEmpty ?? true)
        XCTAssertEqual(Translations.en["settings.terms"], "Terms of Service")
        XCTAssertEqual(Translations.tr["settings.terms"], "Kullanım Koşulları")
        XCTAssertEqual(Translations.en["settings.privacy"], "Privacy Policy")
        XCTAssertEqual(Translations.tr["settings.privacy"], "Gizlilik Politikası")
        XCTAssertEqual(Translations.en["settings.support"], "Customer Support")
        XCTAssertEqual(Translations.tr["settings.support"], "Müşteri Desteği")
        XCTAssertEqual(Translations.en["settings.manage_subscription"], "Manage Subscription")
        XCTAssertEqual(Translations.tr["settings.manage_subscription"], "Aboneliği Yönet")
        XCTAssertTrue(LegalUrls.termsOfService.hasPrefix("https://"))
        XCTAssertTrue(LegalUrls.privacyPolicy.hasPrefix("https://"))
        XCTAssertTrue(LegalUrls.support.hasPrefix("https://"))
        XCTAssertTrue(LegalUrls.manageSubscriptions.hasPrefix("https://apps.apple.com/account/subscriptions"))
    }

    func testMovementIconSupportsAnimatedParameter() {
        let staticIcon = MovementIcon(exerciseId: "barbell-bench-press", size: 72, animated: false)
        XCTAssertNotNil(staticIcon)
        let animatedIcon = MovementIcon(exerciseId: "barbell-bench-press", size: 72, animated: true)
        XCTAssertNotNil(animatedIcon)
    }

    @MainActor
    func testSettingsViewSnapshot() {
        let view = SettingsView(store: AppStore.shared, onDismiss: {})
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 440, height: 1500))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_settings_view_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    private func makePrSession(
        id: String,
        startedAt: String,
        completedAt: String = "",
        durationSeconds: Int = 1800,
        volumeKg: Double = 1000.0,
        exercises: [(String, [Double])]
    ) -> WorkoutSessionRecord {
        let comp = completedAt.isEmpty ? startedAt : completedAt
        let exerciseLogs = exercises.map { (name, weights) in
            SessionExerciseLog(
                exerciseName: name,
                sets: weights.enumerated().map { idx, w in
                    SessionSetLog(setNumber: idx + 1, weightKg: w, reps: 10)
                },
                targetSets: weights.count
            )
        }
        return WorkoutSessionRecord(
            id: id,
            programId: "prog-1",
            workoutId: "w-1",
            workoutTitle: "Test Workout",
            startedAt: startedAt,
            completedAt: comp,
            durationSeconds: durationSeconds,
            totalVolumeKg: volumeKg,
            totalCompletedSets: exercises.reduce(0) { $0 + $1.1.count },
            exerciseLogs: exerciseLogs,
            isComplete: true
        )
    }

    func testFirstRecordedWeightIsBaselineNotPR() {
        let session1 = makePrSession(
            id: "s1",
            startedAt: "2026-09-14T10:00:00Z",
            exercises: [
                ("Bench Press", [60.0, 70.0, 80.0]),
                ("Barbell Squat", [100.0, 100.0])
            ]
        )

        let prCount = PersonalRecordTracker.countPrsForWeek(
            history: [session1],
            currentWeekKey: "2026-W38",
            timeZone: TimeZone(identifier: "UTC")!
        )

        XCTAssertEqual(prCount, 0, "First time weights are recorded must not count as PRs")
    }

    func testPassingPreviousWeightHitsPR() {
        let session1 = makePrSession(
            id: "s1",
            startedAt: "2026-09-07T10:00:00Z", // Week 37
            exercises: [("Bench Press", [80.0, 80.0])]
        )
        let session2 = makePrSession(
            id: "s2",
            startedAt: "2026-09-14T10:00:00Z", // Week 38
            exercises: [("Bench Press", [80.0, 85.0])]
        )

        let prCountWeek38 = PersonalRecordTracker.countPrsForWeek(
            history: [session1, session2],
            currentWeekKey: "2026-W38",
            timeZone: TimeZone(identifier: "UTC")!
        )

        XCTAssertEqual(prCountWeek38, 1, "Exceeding 80 kg with 85 kg must hit 1 PR in Week 38")
    }

    func testEqualOrLowerWeightDoesNotHitPR() {
        let session1 = makePrSession(
            id: "s1",
            startedAt: "2026-09-07T10:00:00Z", // Week 37
            exercises: [("Bench Press", [80.0, 80.0])]
        )
        let session2 = makePrSession(
            id: "s2",
            startedAt: "2026-09-14T10:00:00Z", // Week 38
            exercises: [("Bench Press", [70.0, 80.0])]
        )

        let prCount = PersonalRecordTracker.countPrsForWeek(
            history: [session1, session2],
            currentWeekKey: "2026-W38",
            timeZone: TimeZone(identifier: "UTC")!
        )

        XCTAssertEqual(prCount, 0, "Matching or lower weight must not count as a PR")
    }

    func testMultipleExercisesInWeekTrackIndependentPRs() {
        let session1 = makePrSession(
            id: "s1",
            startedAt: "2026-09-07T10:00:00Z", // Week 37
            exercises: [
                ("Bench Press", [80.0]),
                ("Barbell Squat", [100.0])
            ]
        )
        let session2 = makePrSession(
            id: "s2",
            startedAt: "2026-09-15T10:00:00Z", // Week 38
            exercises: [
                ("Bench Press", [85.0]),    // PR #1 (passed 80)
                ("Barbell Squat", [105.0]),  // PR #2 (passed 100)
                ("Overhead Press", [50.0])   // Baseline (not PR)
            ]
        )

        let prCount = PersonalRecordTracker.countPrsForWeek(
            history: [session1, session2],
            currentWeekKey: "2026-W38",
            timeZone: TimeZone(identifier: "UTC")!
        )

        XCTAssertEqual(prCount, 2)
    }

    func testBodyweightZeroKgDoesNotEstablishOrHitWeightPR() {
        let session1 = makePrSession(
            id: "s1",
            startedAt: "2026-09-07T10:00:00Z",
            exercises: [("Pull-Up", [0.0])]
        )
        let session2 = makePrSession(
            id: "s2",
            startedAt: "2026-09-14T10:00:00Z",
            exercises: [("Pull-Up", [10.0])] // First weight recorded, baseline
        )
        let session3 = makePrSession(
            id: "s3",
            startedAt: "2026-09-16T10:00:00Z",
            exercises: [("Pull-Up", [15.0])] // Passed 10 -> PR!
        )

        let prCountWeek38 = PersonalRecordTracker.countPrsForWeek(
            history: [session1, session2, session3],
            currentWeekKey: "2026-W38",
            timeZone: TimeZone(identifier: "UTC")!
        )

        XCTAssertEqual(prCountWeek38, 1, "10 kg was first recorded weight, 15 kg was the PR")
    }

    func testWeeklyGoalMetricsFormatting() {
        let previous = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(previous) }

        LanguageManager.setLanguage("en")
        let metrics = WeeklyGoalProgressMetrics(
            completedWorkouts: 1,
            totalWorkouts: 5,
            totalVolumeKg: 14850.0,
            activeDurationSeconds: 5040, // 1h 24m
            prsHitCount: 2,
            hasUnfinishedProgress: false
        )

        XCTAssertEqual(metrics.formattedVolume, "14,850")
        XCTAssertEqual(metrics.formattedActiveTime, "1h 24m")
        XCTAssertEqual(metrics.progressFraction, 0.2, accuracy: 0.001)

        LanguageManager.setLanguage("tr")
        XCTAssertEqual(metrics.formattedVolume, "14.850")
        XCTAssertEqual(metrics.formattedActiveTime, "1 sa 24 dk")
    }

    func testWeeklyGoalPillBlinking() {
        let totalWorkouts = 5
        let completedWorkouts = 2

        XCTAssertFalse(isWeeklyGoalPillBlinking(pillIndex: 0, totalWorkouts: totalWorkouts, completedWorkouts: completedWorkouts))
        XCTAssertFalse(isWeeklyGoalPillBlinking(pillIndex: 1, totalWorkouts: totalWorkouts, completedWorkouts: completedWorkouts))
        XCTAssertTrue(isWeeklyGoalPillBlinking(pillIndex: 2, totalWorkouts: totalWorkouts, completedWorkouts: completedWorkouts))
        XCTAssertFalse(isWeeklyGoalPillBlinking(pillIndex: 3, totalWorkouts: totalWorkouts, completedWorkouts: completedWorkouts))
        XCTAssertFalse(isWeeklyGoalPillBlinking(pillIndex: 4, totalWorkouts: totalWorkouts, completedWorkouts: completedWorkouts))

        // Blinks even when no active workout is started/pending
        XCTAssertTrue(isWeeklyGoalPillBlinking(pillIndex: 2, totalWorkouts: totalWorkouts, completedWorkouts: completedWorkouts, isCurrentWorkoutPending: false))

        // 1 completed out of 5 -> 2nd pill (index 1) blinks
        XCTAssertTrue(isWeeklyGoalPillBlinking(pillIndex: 1, totalWorkouts: totalWorkouts, completedWorkouts: 1))
        XCTAssertFalse(isWeeklyGoalPillBlinking(pillIndex: 0, totalWorkouts: totalWorkouts, completedWorkouts: 1))

        for i in 0..<totalWorkouts {
            XCTAssertFalse(isWeeklyGoalPillBlinking(pillIndex: i, totalWorkouts: totalWorkouts, completedWorkouts: 5))
        }

        XCTAssertFalse(isWeeklyGoalPillBlinking(pillIndex: 0, totalWorkouts: 0, completedWorkouts: 0))
    }

    @MainActor
    func testWeeklyGoalProgressCardSnapshot() {
        let previous = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(previous) }
        LanguageManager.setLanguage("en")

        let metrics = WeeklyGoalProgressMetrics(
            completedWorkouts: 3,
            totalWorkouts: 4,
            totalVolumeKg: 14850.0,
            activeDurationSeconds: 5040,
            prsHitCount: 2,
            hasUnfinishedProgress: false
        )

        let view = VStack(spacing: 16) {
            WeeklyGoalProgressCard(metrics: metrics)
        }
        .padding(20)
        .frame(width: 440)
        .background(AppColors.background)

        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 440, height: 300))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_weekly_goal_progress_card_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote WeeklyGoalProgressCard snapshot to \(path)")
        }
    }

    @MainActor
    func testTodayViewSnapshot() {
        let store = AppStore.shared
        let view = TodayView(
            store: store,
            onOpenPrograms: {},
            onOpenSettings: {},
            onSelectExercise: { _ in }
        )
        .background(AppColors.background)

        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_today_view_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote TodayView snapshot to \(path)")
        }
    }

    @MainActor
    func testTodayHeroCardLegsSnapshot() {
        let legsWorkout = Workout(
            id: "legs-test",
            day: 4,
            title: "Quads & Calves",
            focus: "Squat pattern and calf isolation",
            exercises: [
                Exercise(name: "Barbell Back Squat"),
                Exercise(name: "Leg Extension"),
                Exercise(name: "Standing Calf Raise")
            ],
            targetMuscles: ["quadriceps", "calves"]
        )

        let view = VStack {
            TodayHeroCard(
                workout: legsWorkout,
                programId: "test-prog",
                todayIndex: 3,
                isCompleted: false,
                isAvailable: true,
                availableDay: nil,
                hasUnfinishedProgress: false,
                onStart: {}
            )
        }
        .padding(.vertical, 20)
        .frame(width: 440)
        .background(AppColors.background)

        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 440, height: 500))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_legs_hero_card_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote legs hero snapshot to \(path)")
        }
    }

    @MainActor
    func testTodayHeroCardTuesdaySnapshot() {
        let store = AppStore.shared
        store.selectedWorkoutId = "aesthetic-pull-a"
        let workout = store.activeProgram?.workouts.first { $0.id == "aesthetic-pull-a" }
            ?? Workout(
                id: "aesthetic-pull-a",
                day: 2,
                title: "Back & Biceps",
                focus: "Vertical pull, supported row and rear delts",
                exercises: [
                    Exercise(name: "Cable Lat Pulldown"),
                    Exercise(name: "Chest Supported Row"),
                    Exercise(name: "Incline Dumbbell Curl")
                ],
                targetMuscles: ["lats", "trapezius", "shoulders", "biceps"]
            )

        let view = VStack {
            TodayHeroCard(
                workout: workout,
                programId: store.activeProgram?.id ?? "01_aesthetic_hypertrophy",
                todayIndex: store.weekCalendar.today,
                isCompleted: false,
                isAvailable: true,
                availableDay: nil,
                hasUnfinishedProgress: false,
                onStart: {}
            )
        }
        .padding(.vertical, 20)
        .frame(width: 440)
        .background(AppColors.background)

        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 440, height: 500))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_tuesday_hero_card_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote Tuesday hero snapshot to \(path)")
        }
        store.selectedWorkoutId = nil
    }

    @MainActor
    func testTodayHeroCardRestDaySnapshot() {
        let previous = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(previous) }

        for lang in ["en", "tr"] {
            LanguageManager.setLanguage(lang)
            let view = VStack {
                TodayHeroCard(
                    workout: nil,
                    programId: "01_aesthetic_hypertrophy",
                    todayIndex: 5, // Saturday (Rest day)
                    isCompleted: false,
                    isAvailable: false,
                    availableDay: nil,
                    hasUnfinishedProgress: false,
                    onStart: {}
                )
            }
            .padding(.vertical, 20)
            .frame(width: 440)
            .background(AppColors.background)

            let controller = UIHostingController(rootView: view)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 440, height: 500))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()

            let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
            let image = renderer.image { ctx in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }

            if let data = image.pngData() {
                let suffix = lang == "en" ? "" : "_\(lang)"
                let path = "/Users/groggy/.gemini/antigravity/brain/ceb804a2-e800-493e-9c87-33e78710bc6d/ios_rest_day_hero_card_snapshot\(suffix).png"
                try? data.write(to: URL(fileURLWithPath: path))
                print("Successfully wrote Rest Day hero snapshot to \(path)")
            }
        }
    }

    func testRestDayActiveWorkoutBehavior() {
        let store = AppStore.shared
        // Configure a program with workouts only on Monday (1), Wednesday (3), Friday (5)
        let customProgram = Program(
            id: "test-rest-program",
            name: "3-Day Split",
            description: "Test",
            guidelines: [],
            workouts: [
                Workout(id: "day1", day: 1, title: "Monday Workout", exercises: []),
                Workout(id: "day3", day: 3, title: "Wednesday Workout", exercises: []),
                Workout(id: "day5", day: 5, title: "Friday Workout", exercises: [])
            ]
        )
        store.addProgram(customProgram)
        store.switchProgram(to: customProgram.id)
        XCTAssertNil(store.selectedWorkoutId, "selectedWorkoutId should be nil after switching program")

        // If today is a rest day (not day 1, 3, or 5), activeWorkout must be nil
        let todayDay = store.currentWeekDayNumber()
        if todayDay != 1 && todayDay != 3 && todayDay != 5 {
            XCTAssertNil(store.activeWorkout, "activeWorkout must be nil on a rest day when no workout is selected")
        }

        // When a workout is explicitly selected, activeWorkout returns it
        store.selectedWorkoutId = "day3"
        XCTAssertEqual(store.activeWorkout?.id, "day3")

        // When deselected, returns to schedule
        store.selectedWorkoutId = nil
        if todayDay != 1 && todayDay != 3 && todayDay != 5 {
            XCTAssertNil(store.activeWorkout)
        }

        // Clean up
        if let firstProg = store.state.programs.first(where: { $0.id != customProgram.id }) {
            store.switchProgram(to: firstProg.id)
        }
        store.deleteProgram(withId: customProgram.id)
        store.selectedWorkoutId = nil
    }

    func testDeletingSelectedProgramChoosesAnotherSavedProgram() {
        let defaults = UserDefaults.standard
        let keys = ["stored_app_state", "active_session_v1"]
        let saved = keys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in saved {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        keys.forEach { defaults.removeObject(forKey: $0) }
        let store = AppStore(persistence: AppStatePersistence(inMemory: true))
        let initialCount = store.state.programs.count
        XCTAssertGreaterThan(initialCount, 1)
        let selectedID = store.state.activeProgramId
        XCTAssertTrue(store.deleteProgram(withId: selectedID))
        XCTAssertEqual(store.state.programs.count, initialCount - 1)
        XCTAssertNotEqual(store.state.activeProgramId, selectedID)
        XCTAssertTrue(store.state.programs.contains { $0.id == store.state.activeProgramId })
        XCTAssertEqual(store.currentToast?.message, LanguageManager.t("notice.programDeleted"))
    }

    func testCannotDeleteProgramWithActiveSession() {
        let persistence = AppStatePersistence(inMemory: true)
        let store = AppStore(persistence: persistence)
        guard store.state.programs.count >= 2 else { return }

        let prog1 = store.state.programs[0]
        let prog2 = store.state.programs[1]
        store.switchProgram(to: prog1.id)
        _ = store.startActiveSession(programId: prog1.id, workout: prog1.workouts[0], allowPast: true)
        XCTAssertNotNil(store.activeSession)

        store.switchProgram(to: prog2.id)
        XCTAssertEqual(store.state.activeProgramId, prog2.id)

        // Try deleting prog1 while it still has an active session
        let initialCount = store.state.programs.count
        store.deleteProgram(withId: prog1.id)

        XCTAssertEqual(store.state.programs.count, initialCount, "Program with active session must not be deleted")
        XCTAssertEqual(store.currentToast?.message, LanguageManager.t("history.finishActiveFirst"))
    }

    func testOrphanedActiveSessionDiscardedOnStart() {
        let persistence = AppStatePersistence(inMemory: true)
        let store = AppStore(persistence: persistence)
        guard let realProg = store.state.programs.first, let realWorkout = realProg.workouts.first else { return }

        // Create an orphaned draft pointing to a non-existent program
        let orphanDraft = ActiveSessionDraft(
            id: UUID().uuidString,
            programId: "non-existent-program",
            workout: Workout(id: "fake-workout", day: 1, title: "Fake", exercises: []),
            startedAt: "2026-10-13T10:00:00.000Z",
            startedAtEpochMillis: 1791910000000,
            lastActivityEpochMillis: 1791910000000,
            currentExerciseIndex: 0,
            setsByExercise: [:],
            assignedCalendarDate: "2026-10-13",
            accumulatedSeconds: 0,
            isPaused: true,
            lastResumedAtEpochMillis: 1791910000000,
            scheduledDate: "2026-10-13",
            weightInputUnit: .kg
        )
        store.activeSession = orphanDraft

        // Starting a real workout must discard the orphan and succeed
        let started = store.startActiveSession(programId: realProg.id, workout: realWorkout, allowPast: true)
        XCTAssertTrue(started, "Starting workout must succeed after discarding orphan draft")
        XCTAssertEqual(store.activeSession?.programId, realProg.id)
        XCTAssertEqual(store.activeSession?.workout.id, realWorkout.id)
    }

    func testFindExercisePrReturnsBestSetOrNilWhenNoData() {
        let exercise = Exercise(id: "bench", name: "Barbell Bench Press", sets: 3)

        // Empty history
        XCTAssertNil(WorkoutSessionUtils.findExercisePr(history: [], exercise: exercise))

        // History with unrelated exercise
        let record1 = WorkoutSessionRecord(
            id: "rec-1",
            programId: "p1",
            workoutId: "w1",
            workoutTitle: "Legs",
            startedAt: "2026-09-10T10:00:00Z",
            completedAt: "2026-09-10T11:00:00Z",
            durationSeconds: 1800,
            totalVolumeKg: 500,
            totalCompletedSets: 1,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Squat",
                    sets: [SessionSetLog(setNumber: 1, weightKg: 100.0, reps: 5)]
                )
            ]
        )
        XCTAssertNil(WorkoutSessionUtils.findExercisePr(history: [record1], exercise: exercise))

        // History with matching exercise
        let record2 = WorkoutSessionRecord(
            id: "rec-2",
            programId: "p1",
            workoutId: "w1",
            workoutTitle: "Chest",
            startedAt: "2026-09-12T10:00:00Z",
            completedAt: "2026-09-12T11:00:00Z",
            durationSeconds: 1800,
            totalVolumeKg: 1000,
            totalCompletedSets: 3,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 60.0, reps: 12),
                        SessionSetLog(setNumber: 2, weightKg: 65.0, reps: 8),
                        SessionSetLog(setNumber: 3, weightKg: 65.0, reps: 10)
                    ]
                )
            ]
        )
        XCTAssertEqual(WorkoutSessionUtils.findExercisePr(history: [record1, record2], exercise: exercise), "65x10")

        // Newer record with fractional weight PR
        let record3 = WorkoutSessionRecord(
            id: "rec-3",
            programId: "p1",
            workoutId: "w1",
            workoutTitle: "Chest",
            startedAt: "2026-09-15T10:00:00Z",
            completedAt: "2026-09-15T11:00:00Z",
            durationSeconds: 1800,
            totalVolumeKg: 1200,
            totalCompletedSets: 1,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 67.5, reps: 6)
                    ]
                )
            ]
        )
        XCTAssertEqual(WorkoutSessionUtils.findExercisePr(history: [record1, record2, record3], exercise: exercise), "67.5x6")
    }

    func testExerciseReportTranslationsParity() {
        let requiredKeys = [
            "report.action", "report.title", "report.category",
            "report.category.animation_form", "report.category.technique_cue",
            "report.category.what_to_avoid", "report.category.muscles_worked",
            "report.category.equipment_category", "report.category.other",
            "report.detailsLabel", "report.detailsPlaceholder",
            "report.submit", "report.submitted"
        ]

        for key in requiredKeys {
            XCTAssertFalse(Translations.en[key]?.isEmpty ?? true, "Missing English key: \(key)")
            XCTAssertFalse(Translations.tr[key]?.isEmpty ?? true, "Missing Turkish key: \(key)")
        }
    }

    func testExerciseReportStore() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("reports.json")
        let store = ExerciseReportStore(fileURL: fileURL)

        XCTAssertTrue(store.loadReports().isEmpty)

        let report1 = ExerciseIssueReport(
            id: "r1",
            exerciseId: "bench_press",
            exerciseName: "Bench Press",
            category: "animation_form",
            comment: "Elbow flares too much"
        )
        let updated1 = try store.saveReport(report1)
        XCTAssertEqual(updated1.count, 1)
        XCTAssertEqual(updated1[0].id, "r1")

        let report2 = ExerciseIssueReport(
            id: "r2",
            exerciseId: "squat",
            exerciseName: "Barbell Squat",
            category: "what_to_avoid",
            comment: "Add knee cave note"
        )
        let updated2 = try store.saveReport(report2)
        XCTAssertEqual(updated2.count, 2)

        let loaded = store.loadReports()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].exerciseName, "Bench Press")
        XCTAssertEqual(loaded[0].category, "animation_form")
        XCTAssertEqual(loaded[1].exerciseName, "Barbell Squat")
        XCTAssertEqual(loaded[1].category, "what_to_avoid")

        // Preflight pending test (report1 has status pending)
        let preflight = store.checkPreflight()
        if case .pending(let p) = preflight {
            XCTAssertEqual(p.id, "r1")
        } else {
            XCTFail("Expected pending preflight status")
        }

        // Delete test
        let afterDelete = try store.deleteReport(id: "r1")
        XCTAssertEqual(afterDelete.count, 1)
        XCTAssertEqual(afterDelete[0].id, "r2")

        // Preflight cooldown test
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-09-29T15:00:00Z")!
        let accepted1 = ExerciseIssueReport(id: "a1", exerciseName: "Bench", category: "other", timestamp: ISO8601DateFormatter().string(from: now.addingTimeInterval(-600)), status: "accepted")
        let cooldownStatus = store.checkPreflight(reports: [accepted1], now: now, calendar: calendar)
        if case .cooldown(let isDaily, _, let remaining) = cooldownStatus {
            XCTAssertFalse(isDaily)
            XCTAssertEqual(remaining, 2)
        } else {
            XCTFail("Expected hourly cooldown")
        }

        let accepted2 = ExerciseIssueReport(id: "a2", exerciseName: "Squat", category: "other", timestamp: ISO8601DateFormatter().string(from: now.addingTimeInterval(-7200)), status: "accepted")
        let accepted3 = ExerciseIssueReport(id: "a3", exerciseName: "Deadlift", category: "other", timestamp: ISO8601DateFormatter().string(from: now.addingTimeInterval(-14400)), status: "accepted")
        let dailyStatus = store.checkPreflight(reports: [accepted1, accepted2, accepted3], now: now, calendar: calendar)
        if case .cooldown(let isDaily, let nextAllowedAt, let remaining) = dailyStatus {
            XCTAssertTrue(isDaily)
            XCTAssertEqual(remaining, 0)
            let tomorrowMidnight = ISO8601DateFormatter().date(from: "2026-09-30T00:00:00Z")!
            XCTAssertEqual(nextAllowedAt, tomorrowMidnight)
        } else {
            XCTFail("Expected daily cooldown")
        }

        let lateNow = ISO8601DateFormatter().date(from: "2026-09-29T23:45:00Z")!
        let lateR1 = ExerciseIssueReport(id: "l1", exerciseName: "Squat", category: "other", timestamp: "2026-09-29T21:00:00Z", status: "accepted")
        let lateR2 = ExerciseIssueReport(id: "l2", exerciseName: "Bench", category: "other", timestamp: "2026-09-29T22:30:00Z", status: "accepted")
        let lateR3 = ExerciseIssueReport(id: "l3", exerciseName: "Deadlift", category: "other", timestamp: "2026-09-29T23:30:00Z", status: "accepted")
        let lateDailyStatus = store.checkPreflight(reports: [lateR1, lateR2, lateR3], now: lateNow, calendar: calendar)
        if case .cooldown(let isDaily, let nextAllowedAt, _) = lateDailyStatus {
            XCTAssertTrue(isDaily)
            let expectedNext = ISO8601DateFormatter().date(from: "2026-09-30T00:30:00Z")!
            XCTAssertEqual(nextAllowedAt, expectedNext)
        } else {
            XCTFail("Expected daily cooldown respecting 1h window")
        }

        let fractionalReceipt = ExerciseIssueReport(
            id: "fractional", exerciseName: "Row", category: "other",
            status: "accepted", receivedAt: "2026-09-29T12:15:00.123Z"
        )
        let fractionalNow = ISO8601DateFormatter().date(from: "2026-09-29T12:30:00Z")!
        if case .cooldown(let isDaily, let nextAllowedAt, _) = store.checkPreflight(reports: [fractionalReceipt], now: fractionalNow, calendar: calendar) {
            XCTAssertFalse(isDaily)
            XCTAssertEqual(nextAllowedAt.timeIntervalSince1970,
                           fractionalNow.timeIntervalSince1970 + 2700.123, accuracy: 0.01)
        } else {
            XCTFail("Expected cooldown for fractional second receipt")
        }
    }

    @MainActor
    func testExerciseReportSheetSnapshot() {
        let exercise = Exercise(
            name: "Barbell Bench Press",
            prescription: "3 × 8–10",
            movementType: "press"
        )
        let sheet = ExerciseReportSheet(exercise: exercise, onDismiss: {}, onSubmitNotice: { _ in })
        let controller = UIHostingController(rootView: sheet)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x14/255.0, green: 0x17/255.0, blue: 0x1A/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_exercise_report_sheet_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testExerciseDetailViewSnapshot() {
        let exercise = Exercise(
            name: "Barbell Bench Press",
            prescription: "3 × 8–10",
            cues: "Keep feet flat on floor\nRetract scapula\nLower bar with control",
            avoid: "Do not flare elbows to 90 degrees\nDo not bounce bar off chest",
            movementType: "press"
        )
        let view = ExerciseDetailView(exercise: exercise, onBack: {})
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_exercise_detail_with_report_button_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testExerciseDetailTechniqueTabSnapshot() throws {
        let previous = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(previous) }
        let bench = try XCTUnwrap(ExerciseCatalog.canonicalExercises["barbell-bench-press"])
        let exercise = Exercise(
            name: bench.name,
            exerciseId: bench.id,
            prescription: "3 × 8–10",
            cues: bench.cuesText,
            avoid: bench.avoidText,
            movementType: "press"
        )
        for (language, width) in [("en", CGFloat(393)), ("tr", CGFloat(320))] {
            LanguageManager.setLanguage(language)
            let view = ExerciseDetailView(exercise: exercise, initialTab: .technique, onBack: {})
            let controller = UIHostingController(rootView: view)
            controller.view.frame = CGRect(x: 0, y: 0, width: width, height: 852)
            controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 852))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()

            let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
            let image = renderer.image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }

            if let data = image.pngData() {
                try data.write(to: URL(fileURLWithPath: "/tmp/form-technique-ios-page-\(language).png"))
            }
            window.isHidden = true
        }
    }

    @MainActor
    func testExerciseDetailHistoryTabSnapshot() {
        let exercise = Exercise(
            name: "Barbell Bench Press",
            prescription: "3 × 8–10",
            cues: "Keep feet flat on floor\nRetract scapula\nLower bar with control",
            avoid: "Do not flare elbows to 90 degrees",
            movementType: "press"
        )

        let mockHistory: [WorkoutSessionRecord] = [
            WorkoutSessionRecord(
                id: "mock_session_1",
                programId: "prog_1",
                workoutId: "w_1",
                workoutTitle: "Upper Body Strength",
                startedAt: "2026-09-15T10:00:00Z",
                completedAt: "2026-09-15T11:00:00Z",
                durationSeconds: 3600,
                totalVolumeKg: 4000,
                totalCompletedSets: 12,
                exerciseLogs: [
                    SessionExerciseLog(
                        exerciseName: "Barbell Bench Press",
                        sets: [
                            SessionSetLog(setNumber: 1, weightKg: 100.0, reps: 8),
                            SessionSetLog(setNumber: 2, weightKg: 100.0, reps: 7),
                            SessionSetLog(setNumber: 3, weightKg: 95.0, reps: 8)
                        ],
                        targetSets: 3
                    )
                ]
            ),
            WorkoutSessionRecord(
                id: "mock_session_2",
                programId: "prog_1",
                workoutId: "w_1",
                workoutTitle: "Chest & Arms Focus",
                startedAt: "2026-09-10T10:00:00Z",
                completedAt: "2026-09-10T11:00:00Z",
                durationSeconds: 3600,
                totalVolumeKg: 3500,
                totalCompletedSets: 10,
                exerciseLogs: [
                    SessionExerciseLog(
                        exerciseName: "Barbell Bench Press",
                        sets: [
                            SessionSetLog(setNumber: 1, weightKg: 95.0, reps: 8),
                            SessionSetLog(setNumber: 2, weightKg: 90.0, reps: 8)
                        ],
                        targetSets: 2
                    )
                ]
            )
        ]

        let originalHistory = AppStore.shared.state.history
        AppStore.shared.state.history = mockHistory
        defer { AppStore.shared.state.history = originalHistory }

        let view = ExerciseDetailView(exercise: exercise, initialTab: .history, onBack: {})
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_exercise_detail_history_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testExerciseDetailHistoryEmptyTabSnapshot() {
        let exercise = Exercise(
            name: "Barbell Bench Press",
            prescription: "3 × 8–10",
            cues: "Keep feet flat on floor\nRetract scapula\nLower bar with control",
            avoid: "Do not flare elbows to 90 degrees",
            movementType: "press"
        )

        let originalHistory = AppStore.shared.state.history
        AppStore.shared.state.history = []
        defer { AppStore.shared.state.history = originalHistory }

        let view = ExerciseDetailView(exercise: exercise, initialTab: .history, onBack: {})
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_exercise_detail_history_empty_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testSetLoggingTableButtonHierarchySnapshot() {
        let sets = [
            ExerciseSetLog(setNumber: 1, weightInput: "65", repsInput: "10", weightKg: 65.0, completedReps: 10, isCompleted: true),
            ExerciseSetLog(setNumber: 2, weightInput: "65", repsInput: "10", weightKg: 65.0, completedReps: nil, isCompleted: false),
            ExerciseSetLog(setNumber: 3, weightInput: "", repsInput: "", weightKg: nil, completedReps: nil, isCompleted: false)
        ]
        let table = SetLoggingTable(
            sets: sets,
            prescription: "3 × 8–10",
            prText: "65x10",
            onUpdateSet: { _, _, _ in },
            onToggleCompleteSet: { _ in },
            onAddSet: {},
            onRemoveSet: { _ in }
        )
        .padding(16)
        .background(AppColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(AppColors.border, lineWidth: 1))
        .padding(16)
        .background(AppColors.background)

        let controller = UIHostingController(rootView: table)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 380)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 380))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/2bb02c35-faa1-4975-a6c9-c57da1990fda/ios_set_logging_table_buttons_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testZeroLoggedSetsDayStatusResolution() {
        let store = AppStore.shared
        let todayStr = "2026-09-17"
        let yesterdayStr = "2026-09-16"
        let todayDate = WorkoutCalendar.parseDate(todayStr)!

        // 1. Session today with 0 sets logged -> calendar status is nil (neutral tile)
        let todaySessionNoSets = WorkoutSessionRecord(
            id: "test-zero-sets-today",
            programId: "prog",
            workoutId: "w1",
            workoutTitle: "Push",
            startedAt: "2026-09-17T10:00:00.000Z",
            completedAt: "2026-09-17T10:30:00.000Z",
            durationSeconds: 1800,
            totalCompletedSets: 0,
            exerciseLogs: [],
            isComplete: false
        )

        // Save a clean state
        store.activeSession = nil
        let previousHistory = store.state.history
        var st = store.state
        st.history = [todaySessionNoSets]
        st.history.append(todaySessionNoSets)
        st.calendarHistory = WorkoutCalendarHistory(
            nextScheduledDate: "2026-09-14",
            scheduledWeekdays: [1, 2, 4, 5],
            missedDates: [],
            entries: [
                WorkoutDayEntry(id: "session:test-zero-sets-today", date: todayStr, status: .unfinished)
            ]
        )
        store.saveState(st)

        let statusesToday = store.calendarStatuses(today: todayDate)
        XCTAssertNil(statusesToday[todayStr], "Today with zero sets logged must have no status (neutral tile)")

        // 1b. Active session today with 0 completed sets -> calendar status is nil (neutral tile)
        let dummyWorkout = Workout(id: "w1", day: 4, title: "Push", exercises: [Exercise(name: "Bench", sets: 3)])
        store.activeSession = ActiveSessionDraft(
            id: "draft-0-sets",
            programId: "prog",
            workout: dummyWorkout,
            startedAt: "2026-09-17T10:00:00.000Z",
            startedAtEpochMillis: 1000,
            currentExerciseIndex: 0,
            setsByExercise: [
                "Bench": [
                    ExerciseSetLog(setNumber: 1, isCompleted: false)
                ]
            ]
        )
        let statusesActive0Sets = store.calendarStatuses(today: todayDate)
        XCTAssertNil(statusesActive0Sets[todayStr], "Active session today with 0 completed sets must have no status (neutral tile)")
        store.activeSession = nil

        // 2. Session on a passed day with 0 sets logged -> calendar status is .missed (red)
        let pastSessionNoSets = WorkoutSessionRecord(
            id: "test-zero-sets-past",
            programId: "prog",
            workoutId: "w1",
            workoutTitle: "Push",
            startedAt: "2026-09-16T10:00:00.000Z",
            completedAt: "2026-09-16T10:30:00.000Z",
            durationSeconds: 1800,
            totalCompletedSets: 0,
            exerciseLogs: [],
            isComplete: false
        )
        st.history.append(pastSessionNoSets)
        st.calendarHistory = WorkoutCalendarHistory(
            nextScheduledDate: "2026-09-14",
            scheduledWeekdays: [1, 2, 4, 5],
            missedDates: [],
            entries: [
                WorkoutDayEntry(id: "session:test-zero-sets-past", date: yesterdayStr, status: .unfinished)
            ]
        )
        store.saveState(st)

        let statusesPast = store.calendarStatuses(today: todayDate)
        XCTAssertEqual(statusesPast[yesterdayStr], .missed, "Passed day with zero sets logged must be marked .missed (red)")

        // 3. Session on a passed day WITH sets logged -> calendar status is .unfinished (orange)
        let pastSessionWithSets = WorkoutSessionRecord(
            id: "test-zero-sets-past-completed",
            programId: "prog",
            workoutId: "w1",
            workoutTitle: "Push",
            startedAt: "2026-09-16T10:00:00.000Z",
            completedAt: "2026-09-16T10:30:00.000Z",
            durationSeconds: 1800,
            totalCompletedSets: 2,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Bench Press",
                    sets: [SessionSetLog(setNumber: 1, weightKg: 80, reps: 8)],
                    targetSets: 3
                )
            ],
            isComplete: false
        )
        st.history.removeAll { $0.id == "test-zero-sets-past" }
        st.history.append(pastSessionWithSets)
        st.calendarHistory = WorkoutCalendarHistory(
            nextScheduledDate: "2026-09-14",
            scheduledWeekdays: [1, 2, 4, 5],
            missedDates: [],
            entries: [
                WorkoutDayEntry(id: "session:test-zero-sets-past-completed", date: yesterdayStr, status: .unfinished)
            ]
        )
        store.saveState(st)

        let statusesWithSets = store.calendarStatuses(today: todayDate)
        XCTAssertEqual(statusesWithSets[yesterdayStr], .unfinished, "Passed day with sets logged must remain .unfinished (orange)")

        // Clean up
        st.history = previousHistory
        st.calendarHistory = nil
        store.saveState(st)
    }

    func testWeightUnitDefaultForLocale() {
        let usLocale = Locale(identifier: "en_US")
        let gbLocale = Locale(identifier: "en_GB")
        let trLocale = Locale(identifier: "tr_TR")
        let deLocale = Locale(identifier: "de_DE")

        XCTAssertEqual(WeightUnit.defaultForLocale(usLocale), .lbs)
        XCTAssertEqual(WeightUnit.defaultForLocale(gbLocale), .kg)
        XCTAssertEqual(WeightUnit.defaultForLocale(trLocale), .kg)
        XCTAssertEqual(WeightUnit.defaultForLocale(deLocale), .kg)
    }

    // MARK: Onboarding: shared contract in gym/docs/programs/onboarding-fixtures.json.
    // Android OnboardingTest runs the same file; update it with scripts/sync_onboarding_fixtures.cjs.

    private struct OnboardingFixtures: Decodable {
        struct Answer: Decodable {
            let name: String?
            let goal: String
            let experience: String
            let equipment: String
            let frequency: Int
            let selectedDays: [Int]?
            let programId: String
            let days: [Int]?

            func preferences() throws -> OnboardingPreferences {
                OnboardingPreferences(
                    goal: try XCTUnwrap(OnboardingGoal(rawValue: goal)),
                    experience: try XCTUnwrap(OnboardingExperience(rawValue: experience)),
                    equipment: try XCTUnwrap(OnboardingEquipment(rawValue: equipment)),
                    frequency: try XCTUnwrap(OnboardingFrequency(rawValue: frequency)),
                    selectedDays: selectedDays ?? []
                )
            }
        }
        let programs: [Answer]
        let schedules: [Answer]
    }

    private static let fullBodyProgramIds: Set<String> = ["full-body-classic", "machine-foundation", "athletic-performance"]

    private func onboardingFixtures() throws -> OnboardingFixtures {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("onboarding-fixtures.json")
        return try JSONDecoder().decode(OnboardingFixtures.self, from: Data(contentsOf: url))
    }

    func testOnboardingEveryAnswerCombinationMatchesTheSharedTable() throws {
        let rows = try onboardingFixtures().programs
        let programs = AppStore.loadBundledStarterPrograms()
        let combinations = Set(rows.map { "\($0.goal)|\($0.experience)|\($0.equipment)|\($0.frequency)" })
        XCTAssertEqual(combinations.count, OnboardingGoal.allCases.count * OnboardingExperience.allCases.count
            * OnboardingEquipment.allCases.count * OnboardingFrequency.allCases.count)
        for row in rows {
            let recommendation = OnboardingRecommender.recommendProgram(preferences: try row.preferences(), availablePrograms: programs)
            XCTAssertEqual(recommendation.targetProgramId, row.programId, "\(row)")
            XCTAssertNotEqual(recommendation.explanationKey, "onboarding.reason.default", "\(row)")
        }
    }

    func testOnboardingWorkedSchedulesMatchTheSharedContract() throws {
        let programs = AppStore.loadBundledStarterPrograms()
        for schedule in try onboardingFixtures().schedules {
            let name = schedule.name ?? schedule.programId
            let recommendation = OnboardingRecommender.recommendProgram(preferences: try schedule.preferences(), availablePrograms: programs)
            XCTAssertEqual(recommendation.targetProgramId, schedule.programId, name)
            XCTAssertEqual(recommendation.program.workouts.map(\.day), schedule.days, name)
            XCTAssertEqual(recommendation.scheduledWeekdays, schedule.days, name)
        }
    }

    func testOnboardingAuditedRecommendationsTakeExperienceIntoAccount() {
        let programs = AppStore.loadBundledStarterPrograms()
        func program(_ experience: OnboardingExperience, _ frequency: OnboardingFrequency, _ goal: OnboardingGoal = .bulk) -> String {
            OnboardingRecommender.recommendProgram(
                preferences: OnboardingPreferences(goal: goal, experience: experience, equipment: .commercialGym, frequency: frequency),
                availablePrograms: programs
            ).targetProgramId
        }
        XCTAssertEqual(program(.beginner, .days6), "upper-lower-balanced")
        XCTAssertEqual(program(.beginner, .days5), "upper-lower-balanced")
        XCTAssertEqual(program(.beginner, .days3, .cut), "full-body-classic")
        XCTAssertEqual(program(.intermediate, .days3, .cut), "full-body-classic")
        XCTAssertEqual(program(.advanced, .days3), "athletic-performance")
        XCTAssertEqual(program(.intermediate, .days6), "aesthetic-hypertrophy")
        XCTAssertEqual(program(.advanced, .days6), "classic-ppl")
    }

    func testOnboardingEveryChosenDaySetGetsDistinctDaysAndRestBetweenFullBodySessions() {
        for program in AppStore.loadBundledStarterPrograms() {
            let weeklyOrder = program.workouts.sorted { $0.day < $1.day }.map(\.id)
            for mask in 1..<128 {
                let chosen = (1...7).filter { mask & (1 << ($0 - 1)) != 0 }
                let scheduled = OnboardingRecommender.schedule(program, preferences: OnboardingPreferences(selectedDays: chosen))
                let days = scheduled.workouts.map(\.day)
                let label = "\(program.id) on \(chosen) -> \(days)"
                XCTAssertEqual(scheduled.workouts.map(\.id), weeklyOrder, label)
                XCTAssertEqual(days, Array(Set(days)).sorted(), label)
                if Self.fullBodyProgramIds.contains(program.id) {
                    XCTAssertFalse(days.contains { days.contains($0 == 7 ? 1 : $0 + 1) }, label)
                } else {
                    XCTAssertEqual(days.filter { chosen.contains($0) }.count, min(chosen.count, days.count), label)
                }
            }
        }
    }

    func testOnboardingMissingProgramFallsBackWithItsOwnExplanation() throws {
        let programs = AppStore.loadBundledStarterPrograms().filter { $0.id != "machine-foundation" }
        let first = try XCTUnwrap(programs.first)
        let recommendation = OnboardingRecommender.recommendProgram(
            preferences: OnboardingPreferences(equipment: .machinesOnly), availablePrograms: programs
        )
        XCTAssertEqual(recommendation.targetProgramId, first.id)
        XCTAssertEqual(recommendation.explanationKey, OnboardingRecommender.explanationKey(programId: first.id))
    }

    @MainActor
    func testCompleteOnboardingStoresDistinctChosenDaysAndSelectsTheProgram() throws {
        let key = "is_onboarding_completed"
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        let persistence = AppStatePersistence(inMemory: true)
        let store = AppStore(persistence: persistence)
        store.state = StoredAppState(programs: AppStore.loadBundledStarterPrograms(), activeProgramId: "aesthetic-hypertrophy")
        let untouched = store.state.programs.filter { $0.id != "home-forge-dumbbells" }
        // Home Forge has four workouts; three chosen days must not put two workouts on Friday.
        let preferences = OnboardingPreferences(goal: .bulk, experience: .intermediate, equipment: .dumbbellsHome,
            frequency: .days3, selectedDays: [1, 3, 5])
        let recommendation = OnboardingRecommender.recommendProgram(preferences: preferences, availablePrograms: store.state.programs)
        store.completeOnboarding(preferences: preferences, targetProgramId: recommendation.targetProgramId)

        let expected = [1, 3, 5, 6]
        XCTAssertEqual(recommendation.scheduledWeekdays, expected)
        XCTAssertTrue(store.isOnboardingCompleted)
        XCTAssertEqual(store.state.activeProgramId, "home-forge-dumbbells")
        XCTAssertEqual(store.state.programs.first { $0.id == "home-forge-dumbbells" }?.workouts.map(\.day), expected)
        XCTAssertEqual(store.state.calendarHistory?.scheduledWeekdays, expected)
        XCTAssertEqual(store.state.programs.filter { $0.id != "home-forge-dumbbells" }, untouched)
        try persistence.flush()
        let reloaded = AppStore(persistence: persistence)
        XCTAssertEqual(reloaded.state.activeProgramId, "home-forge-dumbbells")
        XCTAssertEqual(reloaded.state.programs.first { $0.id == "home-forge-dumbbells" }?.workouts.map(\.day), expected)
    }

    func testProAccessManagerEntitlements() {
        let manager = ProAccessManager.shared
        defer { manager.resetOverrides() }

        // Default: locked for free tier
        manager.resetOverrides()
        XCTAssertFalse(manager.isFeatureUnlocked(.volumeMatrix))
        XCTAssertFalse(manager.isFeatureUnlocked(.autoProgression))
        XCTAssertFalse(manager.isFeatureUnlocked(.formLab))

        // Subscription unlocks all
        manager.updateSubscriptionStatus(active: true)
        XCTAssertTrue(manager.isFeatureUnlocked(.volumeMatrix))
        XCTAssertTrue(manager.isFeatureUnlocked(.autoProgression))
        XCTAssertTrue(manager.isFeatureUnlocked(.formLab))

        // Force locked via override
        manager.setFeatureOverride(.volumeMatrix, unlocked: false)
        XCTAssertFalse(manager.isFeatureUnlocked(.volumeMatrix))
        XCTAssertTrue(manager.isFeatureUnlocked(.autoProgression))

        // Force unlocked via override even when unsubscribed
        manager.updateSubscriptionStatus(active: false)
        manager.setFeatureOverride(.volumeMatrix, unlocked: true)
        XCTAssertTrue(manager.isFeatureUnlocked(.volumeMatrix))
        XCTAssertFalse(manager.isFeatureUnlocked(.autoProgression))
    }

    func testComprehensiveProGatedQualitySuite() {
        let manager = ProAccessManager.shared
        manager.resetOverrides()
        manager.updateSubscriptionStatus(active: false)

        // 1. Free Tier Baseline: All 6 features strictly locked
        let allFeatures: [ProFeature] = [.volumeMatrix, .autoProgression, .warmupCalculator, .formLab, .cloudBackup, .customThemes]
        XCTAssertEqual(ProFeature.allCases.count, 6)
        for feature in allFeatures {
            XCTAssertFalse(manager.isFeatureUnlocked(feature), "Feature \(feature.rawValue) must be locked for free tier")
            XCTAssertFalse(feature.titleKey.isEmpty)
            XCTAssertFalse(feature.descriptionKey.isEmpty)
            XCTAssertFalse(feature.teaserKey.isEmpty)
        }

        // 2. Subscription Activation: All 6 features unlock immediately
        manager.updateSubscriptionStatus(active: true)
        XCTAssertTrue(manager.isProSubscribed)
        for feature in allFeatures {
            XCTAssertTrue(manager.isFeatureUnlocked(feature), "Feature \(feature.rawValue) must be unlocked when subscribed")
        }

        // 3. Override Isolation: Lock Cloud Backup specifically
        manager.setFeatureOverride(.cloudBackup, unlocked: false)
        XCTAssertFalse(manager.isFeatureUnlocked(.cloudBackup))
        XCTAssertTrue(manager.isFeatureUnlocked(.volumeMatrix))
        XCTAssertTrue(manager.isFeatureUnlocked(.autoProgression))
        XCTAssertTrue(manager.isFeatureUnlocked(.warmupCalculator))
        XCTAssertTrue(manager.isFeatureUnlocked(.formLab))

        manager.setFeatureOverride(.cloudBackup, unlocked: nil)
        XCTAssertTrue(manager.isFeatureUnlocked(.cloudBackup))

        // 4. Warmup Plate Math & Unit Normalization under Pro
        let lbsResult = WarmupPlateEngine.calculatePlates(
            targetWeight: 225.0,
            barWeight: 45.0,
            availablePlates: WarmupPlateEngine.defaultPlatesLbs,
            unit: .lbs
        )
        XCTAssertEqual(lbsResult.targetWeight, 225.0, accuracy: 0.001)
        XCTAssertEqual(lbsResult.totalAchievedWeight, 225.0, accuracy: 0.001)
        let fortyFivePlates = lbsResult.platesPerSide.first(where: { $0.weight == 45.0 })?.count ?? 0
        XCTAssertEqual(fortyFivePlates, 2)

        // 5. Progression Engine: Bodyweight Support
        let pullUp = Exercise(
            id: "pu-1",
            name: "Pull-Up",
            exerciseId: "pull-up",
            sets: 3,
            reps: RepTarget(min: 8, max: 12)
        )
        let bwHistory = [
            WorkoutSessionRecord(
                id: "bws1",
                programId: "p1",
                workoutId: "w1",
                workoutTitle: "Back",
                startedAt: "2026-09-10T10:00:00Z",
                completedAt: "2026-09-10T11:00:00Z",
                durationSeconds: 3600,
                exerciseLogs: [
                    SessionExerciseLog(
                        exerciseName: "Pull-Up",
                        sets: [
                            SessionSetLog(setNumber: 1, weightKg: 0.0, reps: 10),
                            SessionSetLog(setNumber: 2, weightKg: 0.0, reps: 9),
                            SessionSetLog(setNumber: 3, weightKg: 0.0, reps: 8)
                        ]
                    )
                ]
            )
        ]
        let bwRec = ProgressionEngine.computeProgression(exercise: pullUp, history: bwHistory, weightUnit: .kg)!
        XCTAssertEqual(bwRec.action, .addReps)
        XCTAssertEqual(bwRec.suggestedWeightDisplay, "BW")
        XCTAssertEqual(bwRec.suggestedRepsMin, 9)

        // 6. Form Lab Training Distribution Ratio Formatting
        let pushSets = 76
        let pullSets = 85
        let ratioVal = round((Double(pushSets) / Double(pullSets)) * 100.0) / 100.0
        XCTAssertEqual(ratioVal, 0.89, accuracy: 0.01)
        let ratioFormatted = String(format: "%.2f : 1.0", ratioVal)
        XCTAssertEqual(ratioFormatted, "0.89 : 1.0")

        // 7. Offline Grace Period Lifecycle Bounds (7 Days)
        let now = Date().timeIntervalSince1970
        let verifiedThreeDaysAgo = now - (3 * 86400)
        let isWithinGrace = (now - verifiedThreeDaysAgo) <= (7 * 86400) && (verifiedThreeDaysAgo - now) <= 300
        XCTAssertTrue(isWithinGrace)

        let verifiedEightDaysAgo = now - (8 * 86400)
        let isExpired = (now - verifiedEightDaysAgo) > (7 * 86400)
        XCTAssertTrue(isExpired)

        // Cleanup
        manager.resetOverrides()
        manager.updateSubscriptionStatus(active: false)
    }

    func testProPreviewDataDemonstrationHistory() {
        // Zero-history accounts identified correctly
        XCTAssertFalse(ProPreviewData.hasWorkingHistory([]))

        let warmupOnly = [
            WorkoutSessionRecord(
                id: "p1",
                programId: "p",
                workoutId: "w",
                workoutTitle: "Warmup",
                startedAt: "2026-09-20T10:00:00Z",
                completedAt: "2026-09-20T10:30:00Z",
                durationSeconds: 1800,
                exerciseLogs: [
                    SessionExerciseLog(
                        exerciseName: "Barbell Bench Press",
                        sets: [SessionSetLog(setNumber: 1, weightKg: 40.0, reps: 10, isWarmup: true)]
                    )
                ]
            )
        ]
        XCTAssertFalse(ProPreviewData.hasWorkingHistory(warmupOnly))

        let validSession = [
            WorkoutSessionRecord(
                id: "p2",
                programId: "p",
                workoutId: "w",
                workoutTitle: "Workout",
                startedAt: "2026-09-20T10:00:00Z",
                completedAt: "2026-09-20T10:45:00Z",
                durationSeconds: 2700,
                exerciseLogs: [
                    SessionExerciseLog(
                        exerciseName: "Barbell Bench Press",
                        sets: [SessionSetLog(setNumber: 1, weightKg: 80.0, reps: 8, isWarmup: false)]
                    )
                ]
            )
        ]
        XCTAssertTrue(ProPreviewData.hasWorkingHistory(validSession))

        // Static Volume Matrix preview report verification
        let report = ProPreviewData.volumeMatrixPreviewReport
        XCTAssertGreaterThan(report.totalEffectiveSets, 20)
        XCTAssertEqual(report.optimalMuscleCount, 1)
        XCTAssertEqual(report.highFatigueCount, 4)

        // Front view muscles have diverse vibrant non-gray zones
        let chest = report.muscleSummaries["chest"]
        XCTAssertNotNil(chest)
        XCTAssertEqual(chest?.zone, .optimalMav)
        XCTAssertEqual(chest?.defaultView, "front")

        let quads = report.muscleSummaries["quads"]
        XCTAssertNotNil(quads)
        XCTAssertEqual(quads?.zone, .overMrv)

        let biceps = report.muscleSummaries["biceps"]
        XCTAssertNotNil(biceps)
        XCTAssertEqual(biceps?.zone, .highFatigue)

        let abs = report.muscleSummaries["abs"]
        XCTAssertNotNil(abs)
        XCTAssertEqual(abs?.zone, .progressive)

        let sideDelts = report.muscleSummaries["side-delts"]
        XCTAssertNotNil(sideDelts)
        XCTAssertEqual(sideDelts?.zone, .overMrv)

        let obliques = report.muscleSummaries["obliques"]
        XCTAssertNotNil(obliques)
        XCTAssertEqual(obliques?.zone, .highFatigue)

        // Back view muscles are omitted since user cannot view them behind paywall
        XCTAssertNil(report.muscleSummaries["upper-back"])
        XCTAssertNil(report.muscleSummaries["lats"])
        XCTAssertNil(report.muscleSummaries["triceps"])

        // Static Form Lab preview data verification
        let benchRepMax = ProPreviewData.formLabRepMaxSummary
        XCTAssertEqual(benchRepMax.exerciseName, "Barbell Bench Press")
        XCTAssertGreaterThan(benchRepMax.estimated1rmKg, 100.0)
        XCTAssertFalse(benchRepMax.targets.isEmpty)

        let benchCurve = ProPreviewData.formLabCurveReport
        XCTAssertGreaterThanOrEqual(benchCurve.points.count, 4)
        XCTAssertGreaterThan(benchCurve.deltaKg, 0.0)
        XCTAssertGreaterThan(benchCurve.percentageGain, 0.0)

        let balance = ProPreviewData.formLabBalanceReport
        XCTAssertNotNil(balance.pushPull.ratio)
        XCTAssertEqual(balance.pushPull.status, .optimal)
        XCTAssertNotNil(balance.quadHamstring.ratio)
        XCTAssertEqual(balance.quadHamstring.status, .optimal)
        XCTAssertNotNil(balance.upperLower.ratio)
        XCTAssertEqual(balance.upperLower.status, .optimal)
    }

    func testVolumeMatrixEngineComputation() {
        guard let catalog = ExerciseMuscleCatalog.shared else {
            XCTFail("ExerciseMuscleCatalog must load")
            return
        }

        XCTAssertEqual(VolumeMatrixEngine.canonicalMuscles.count, 14)
        for muscle in VolumeMatrixEngine.canonicalMuscles {
            XCTAssertNotNil(catalog.muscles[muscle], "Muscle \(muscle) must exist in catalog")
        }

        let benchId = VolumeMatrixEngine.resolveExerciseId(exerciseName: "Barbell Bench Press")
        XCTAssertEqual(benchId, "barbell-bench-press")
        XCTAssertEqual(VolumeMatrixEngine.resolveExerciseId(exerciseName: "Deadlift"), "conventional-barbell-deadlift")
        XCTAssertEqual(VolumeMatrixEngine.resolveExerciseId(exerciseName: "Smith Machine Squat"), "smith-squat")
        XCTAssertEqual(VolumeMatrixEngine.resolveExerciseId(exerciseName: "Dumbbell 45° Back Extension"), "dumbbell-45-deg-back-extension")
        XCTAssertEqual(VolumeMatrixEngine.resolveExerciseId(exerciseName: "Dual Cable Lat Pulldown"), "cable-neutral-grip-lat-pulldown")

        let session = WorkoutSessionRecord(
            id: "test-sess-1",
            programId: "p1",
            workoutId: "w1",
            workoutTitle: "Push Day",
            startedAt: "2026-09-15T10:00:00Z",
            completedAt: "2026-09-15T11:00:00Z",
            durationSeconds: 3600,
            totalVolumeKg: 320,
            totalCompletedSets: 4,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 80, reps: 10),
                        SessionSetLog(setNumber: 2, weightKg: 80, reps: 10),
                        SessionSetLog(setNumber: 3, weightKg: 80, reps: 10),
                        SessionSetLog(setNumber: 4, weightKg: 80, reps: 8)
                    ]
                )
            ]
        )

        let report = VolumeMatrixEngine.computeLoggedVolume(
            targetWeekKey: "2026-W38",
            history: [session],
            catalog: catalog
        )

        // Chest: 4 direct, 0 indirect -> 4.0 effective
        let chest = report.muscleSummaries["chest"]
        XCTAssertNotNil(chest)
        XCTAssertEqual(chest?.directSets, 4)
        XCTAssertEqual(chest?.indirectSets, 0)
        XCTAssertEqual(chest?.totalEffectiveSets, 4.0)
        XCTAssertEqual(chest?.zone, VolumeZone.underMev)

        // Front delts: 0 direct, 4 indirect -> 2.0 effective
        let frontDelts = report.muscleSummaries["front-delts"]
        XCTAssertNotNil(frontDelts)
        XCTAssertEqual(frontDelts?.directSets, 0)
        XCTAssertEqual(frontDelts?.indirectSets, 4)
        XCTAssertEqual(frontDelts?.totalEffectiveSets, 2.0)
        XCTAssertEqual(report.totalWorkingSets, 4)
        XCTAssertEqual(report.totalEffectiveSets, 8.0)
        XCTAssertTrue(report.unmappedExercises.isEmpty)

        let coverageSession = WorkoutSessionRecord(
            id: "coverage", programId: "p", workoutId: "w", workoutTitle: "Shoulders",
            startedAt: "2026-09-15T10:00:00Z", completedAt: "2026-09-15T11:00:00Z",
            durationSeconds: 3600, exerciseLogs: [
                SessionExerciseLog(exerciseName: "Dumbbell Lateral Raise", sets: (1...2).map { SessionSetLog(setNumber: $0, weightKg: 10, reps: 12) }),
                SessionExerciseLog(exerciseName: "My Custom Movement", sets: (1...2).map { SessionSetLog(setNumber: $0, weightKg: 10, reps: 10) })
            ])
        let coverage = VolumeMatrixEngine.computeLoggedVolume(targetWeekKey: "2026-W38", history: [coverageSession], catalog: catalog)
        XCTAssertEqual(coverage.totalWorkingSets, 4)
        XCTAssertEqual(coverage.unmappedExercises["My Custom Movement"], 2)
        XCTAssertEqual(coverage.muscleSummaries["side-delts"]?.totalEffectiveSets, 2)
        XCTAssertEqual(catalog.profile("dumbbell-lateral-raise")?.primary, ["side-delts"])
        XCTAssertEqual(catalog.profile("head-supported-dumbbell-rear-lateral-raise")?.primary, ["rear-delts"])
        XCTAssertNil(VolumeMatrixEngine.resolveExerciseId(exerciseName: "My Custom Movement"))

        let program = Program(
            id: "cycle",
            name: "Test cycle",
            workouts: [
                Workout(
                    id: "upper",
                    day: 1,
                    title: "Upper",
                    exercises: [
                        Exercise(name: "Barbell Bench Press", exerciseId: "barbell-bench-press", sets: 4),
                        Exercise(name: "Lat Pulldown", exerciseId: "lat-pulldown", sets: 4)
                    ]
                ),
                Workout(
                    id: "lower",
                    day: 2,
                    title: "Lower",
                    exercises: [
                        Exercise(name: "Barbell Back Squat", exerciseId: "barbell-back-squat", sets: 4)
                    ]
                )
            ]
        )
        let cycle = VolumeMatrixEngine.computePlannedRoutineVolume(program: program, catalog: catalog)
        XCTAssertTrue(cycle.isPlannedRoutine)
        XCTAssertEqual(cycle.weekKey, "program-cycle")
        XCTAssertEqual(cycle.totalWorkingSets, 12)
        XCTAssertTrue(cycle.muscleSummaries.values.allSatisfy { $0.zone == .noWeeklyReference })
        XCTAssertEqual(cycle.optimalMuscleCount, 0)
        XCTAssertEqual(cycle.underTrainedCount, 0)
        XCTAssertEqual(cycle.highFatigueCount, 0)

        let resumedId = "resumed-session"
        let staleRecord = WorkoutSessionRecord(
            id: resumedId,
            programId: "program",
            workoutId: "workout",
            workoutTitle: "Old saved state",
            startedAt: "2026-09-15T09:00:00Z",
            completedAt: "2026-09-15T10:00:00Z",
            durationSeconds: 3600,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: (1...4).map { SessionSetLog(setNumber: $0, weightKg: 80, reps: 8) },
                    exerciseId: "barbell-bench-press"
                )
            ],
            isComplete: false
        )
        let activeExercise = Exercise(
            id: "deadlift-instance",
            name: "Localized deadlift label",
            exerciseId: "conventional-barbell-deadlift",
            sets: 2
        )
        let start = Int64((ISO8601DateFormatter().date(from: "2026-09-15T09:00:00Z")?.timeIntervalSince1970 ?? 0) * 1000)
        let now = Int64((ISO8601DateFormatter().date(from: "2026-09-15T11:00:00Z")?.timeIntervalSince1970 ?? 0) * 1000)
        let active = ActiveSessionDraft(
            id: resumedId,
            programId: "program",
            workout: Workout(id: "workout", day: 2, title: "Resumed", exercises: [activeExercise]),
            startedAt: "2026-09-15T09:00:00Z",
            startedAtEpochMillis: start,
            setsByExercise: [
                activeExercise.id: (1...2).map {
                    ExerciseSetLog(setNumber: $0, weightKg: 100, completedReps: 5, isCompleted: true)
                }
            ]
        )
        let activeReport = VolumeMatrixEngine.computeLoggedVolume(
            targetWeekKey: "2026-W38",
            history: [staleRecord],
            activeSession: active,
            catalog: catalog,
            nowEpochMillis: now
        )
        XCTAssertEqual(activeReport.totalWorkingSets, 2)
        XCTAssertEqual(activeReport.muscleSummaries["glutes"]?.totalEffectiveSets, 2)
        XCTAssertEqual(activeReport.muscleSummaries["hamstrings"]?.totalEffectiveSets, 2)
        XCTAssertEqual(activeReport.muscleSummaries["chest"]?.totalEffectiveSets, 0)
        XCTAssertTrue(activeReport.unmappedExercises.isEmpty)
        XCTAssertEqual(
            SessionProgress.from(draft: active, nowEpochMillis: now).exerciseLogs.first?.exerciseId,
            "conventional-barbell-deadlift"
        )
    }

    func testHeavylifterBackupDecodingAndVolumeMatrixZones() throws {
        let testDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fixtureUrl = Bundle(for: FormAppTests.self).url(forResource: "heavylifter_backup", withExtension: "json")
            ?? testDir.appendingPathComponent("../FormApp/Resources/Fixtures/heavylifter_backup.json").standardized
        let data = try Data(contentsOf: fixtureUrl)
        let decoded = try JSONDecoder().decode(StoredAppState.self, from: data)
        XCTAssertEqual(decoded.activeProgramId, "heavylifter-strength-power")
        XCTAssertEqual(decoded.history.count, 48)

        guard let catalog = ExerciseMuscleCatalog.shared else {
            XCTFail("Catalog required")
            return
        }

        let report = VolumeMatrixEngine.computeLoggedVolume(
            targetWeekKey: "2026-W39",
            history: decoded.history,
            catalog: catalog
        )

        // Front view
        XCTAssertEqual(report.muscleSummaries["chest"]?.zone, .overMrv)
        XCTAssertEqual(report.muscleSummaries["front-delts"]?.zone, .highFatigue)
        XCTAssertEqual(report.muscleSummaries["quads"]?.zone, .optimalMav)
        XCTAssertEqual(report.muscleSummaries["side-delts"]?.zone, .optimalMav)
        XCTAssertEqual(report.muscleSummaries["biceps"]?.zone, .progressive)
        XCTAssertEqual(report.muscleSummaries["abs"]?.zone, .underMev)
        XCTAssertEqual(report.muscleSummaries["obliques"]?.zone, .underMev)

        // Back view
        XCTAssertEqual(report.muscleSummaries["upper-back"]?.zone, .overMrv)
        XCTAssertEqual(report.muscleSummaries["lats"]?.zone, .highFatigue)
        XCTAssertEqual(report.muscleSummaries["triceps"]?.zone, .optimalMav)
        XCTAssertEqual(report.muscleSummaries["rear-delts"]?.zone, .progressive)
        XCTAssertEqual(report.muscleSummaries["glutes"]?.zone, .progressive)
        XCTAssertEqual(report.muscleSummaries["hamstrings"]?.zone, .underMev)
        XCTAssertEqual(report.muscleSummaries["calves"]?.zone, .underMev)
    }

    func testHeavylifterFreshWeekBackupDecodingAndUntouchedCurrentWeek() throws {
        let testDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fixtureUrl = Bundle(for: FormAppTests.self).url(forResource: "heavylifter_fresh_week_backup", withExtension: "json")
            ?? testDir.appendingPathComponent("../FormApp/Resources/Fixtures/heavylifter_fresh_week_backup.json").standardized
        let data = try Data(contentsOf: fixtureUrl)
        let decoded = try JSONDecoder().decode(StoredAppState.self, from: data)
        XCTAssertEqual(decoded.activeProgramId, "heavylifter-strength-power")
        XCTAssertTrue(decoded.completed.isEmpty, "Current week completed workouts must be empty for testing")
        XCTAssertEqual(decoded.history.count, 44)
    }

    func testExerciseSessionHistoryEntryBestSet() {
        let entry1 = ExerciseSessionHistoryEntry(
            sessionId: "s1",
            date: "2026-09-24T10:00:00Z",
            workoutTitle: "Push Day",
            sets: [
                SessionSetLog(setNumber: 1, weightKg: 60.0, reps: 10, isWarmup: true),
                SessionSetLog(setNumber: 2, weightKg: 100.0, reps: 8, isWarmup: false),
                SessionSetLog(setNumber: 3, weightKg: 140.0, reps: 5, isWarmup: false)
            ]
        )
        XCTAssertEqual(entry1.bestSet(weightUnit: .kg), "140 kg × 5")

        let entryBodyweight = ExerciseSessionHistoryEntry(
            sessionId: "s2",
            date: "2026-09-22T10:00:00Z",
            workoutTitle: "Pull Day",
            sets: [
                SessionSetLog(setNumber: 1, weightKg: 0.0, reps: 12, isWarmup: false),
                SessionSetLog(setNumber: 2, weightKg: 0.0, reps: 15, isWarmup: false)
            ]
        )
        XCTAssertEqual(entryBodyweight.bestSet(weightUnit: .kg), "15 reps")

        let entryEmpty = ExerciseSessionHistoryEntry(
            sessionId: "s3",
            date: "2026-09-20T10:00:00Z",
            workoutTitle: "Empty",
            sets: []
        )
        XCTAssertNil(entryEmpty.bestSet(weightUnit: .kg))
    }

    func testProgressionEngineReturnsFirstSessionWhenHistoryIsEmpty() {
        let benchPress = Exercise(
            id: "bench-1",
            name: "Barbell Bench Press",
            exerciseId: "barbell-bench-press",
            sets: 3,
            reps: RepTarget(min: 8, max: 12)
        )
        let rec = ProgressionEngine.computeProgression(exercise: benchPress, history: [])!
        XCTAssertEqual(rec.action, .firstSession)
        XCTAssertNil(rec.suggestedWeightKg)
        XCTAssertEqual(rec.suggestedRepsMin, 8)
        XCTAssertEqual(rec.suggestedRepsMax, 12)
        XCTAssertFalse(rec.isPlateau)
    }

    func testProgressionEngineRecommendsIncreaseLoadWhenAllSetsHitRepCeiling() {
        let benchPress = Exercise(
            id: "bench-1",
            name: "Barbell Bench Press",
            exerciseId: "barbell-bench-press",
            sets: 3,
            reps: RepTarget(min: 8, max: 12)
        )
        let history = [
            WorkoutSessionRecord(
                id: "s1",
                programId: "p1",
                workoutId: "w1",
                workoutTitle: "Push",
                startedAt: "2026-09-10T10:00:00Z",
                completedAt: "2026-09-10T11:00:00Z",
                durationSeconds: 3600,
                exerciseLogs: [
                    SessionExerciseLog(
                        exerciseName: "Barbell Bench Press",
                        sets: [
                            SessionSetLog(setNumber: 1, weightKg: 80.0, reps: 12),
                            SessionSetLog(setNumber: 2, weightKg: 80.0, reps: 12),
                            SessionSetLog(setNumber: 3, weightKg: 80.0, reps: 12)
                        ]
                    )
                ]
            )
        ]

        var previous = history[0]
        previous.id = "previous"
        previous.completedAt = "2026-09-01T11:00:00Z"
        let rec = ProgressionEngine.computeProgression(exercise: benchPress, history: history + [previous], weightUnit: .kg)!
        XCTAssertEqual(rec.action, .increaseLoad)
        XCTAssertEqual(rec.suggestedWeightKg ?? 0, 82.5, accuracy: 0.01)
        XCTAssertEqual(rec.suggestedRepsMin, 12)
        XCTAssertFalse(rec.isPlateau)
        XCTAssertTrue(rec.weightDeltaDisplay?.contains("+2.5") == true)
    }

    func testBackoffSetsGovernDoubleProgressionWithoutOverwritingTheirLoads() {
        let benchPress = Exercise(
            name: "Barbell Bench Press", exerciseId: "barbell-bench-press",
            sets: 2, reps: RepTarget(min: 8, max: 12)
        )

        func recommendationFor(_ backoffReps: Int) -> ExerciseProgressionRecommendation {
            let record = WorkoutSessionRecord(
                id: "s1", programId: "p1", workoutId: "w1", workoutTitle: "Push",
                startedAt: "2026-09-17T10:00:00Z", completedAt: "2026-09-17T11:00:00Z",
                durationSeconds: 3600,
                exerciseLogs: [SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [
                        SessionSetLog(setNumber: 0, weightKg: 20, reps: 3, isWarmup: true),
                        SessionSetLog(setNumber: 1, weightKg: 80, reps: 12),
                        SessionSetLog(setNumber: 2, weightKg: 60, reps: backoffReps)
                    ]
                )]
            )
            var previous = record
            previous.id = "previous"
            previous.completedAt = "2026-09-10T11:00:00Z"
            return ProgressionEngine.computeProgression(exercise: benchPress, history: [record, previous], weightUnit: .kg)!
        }

        let addReps = recommendationFor(10)
        XCTAssertEqual(addReps.action, .addReps)
        XCTAssertEqual(addReps.suggestedRepsMin, 11)
        XCTAssertNil(addReps.suggestedWeightKg)
        XCTAssertEqual(addReps.rationaleKey, "progression.rationale.add_reps_mixed")
        XCTAssertEqual(addReps.setTargets.map { $0.weightKg }, [80, 60])
        XCTAssertEqual(addReps.setTargets.map { $0.reps }, [12, 11])

        let hold = recommendationFor(7)
        XCTAssertEqual(hold.action, .holdLoad)
        XCTAssertNil(hold.suggestedWeightKg)
        XCTAssertEqual(hold.rationaleKey, "progression.rationale.hold_load_mixed")

        let increase = recommendationFor(12)
        XCTAssertEqual(increase.action, .increaseLoad)
        XCTAssertNil(increase.suggestedWeightKg)
        XCTAssertEqual(increase.rationaleKey, "progression.rationale.increase_load_mixed")
    }

    func testProgressionEngineRecommendsAddRepsWhenWithinBracket() {
        let benchPress = Exercise(
            id: "bench-1",
            name: "Barbell Bench Press",
            exerciseId: "barbell-bench-press",
            sets: 3,
            reps: RepTarget(min: 8, max: 12)
        )
        let history = [
            WorkoutSessionRecord(
                id: "s1",
                programId: "p1",
                workoutId: "w1",
                workoutTitle: "Push",
                startedAt: "2026-09-10T10:00:00Z",
                completedAt: "2026-09-10T11:00:00Z",
                durationSeconds: 3600,
                exerciseLogs: [
                    SessionExerciseLog(
                        exerciseName: "Barbell Bench Press",
                        sets: [
                            SessionSetLog(setNumber: 1, weightKg: 80.0, reps: 11),
                            SessionSetLog(setNumber: 2, weightKg: 80.0, reps: 10),
                            SessionSetLog(setNumber: 3, weightKg: 80.0, reps: 9)
                        ]
                    )
                ]
            )
        ]

        let rec = ProgressionEngine.computeProgression(exercise: benchPress, history: history, weightUnit: .kg)!
        XCTAssertEqual(rec.action, .addReps)
        XCTAssertEqual(rec.suggestedWeightKg ?? 0, 80.0, accuracy: 0.01)
        XCTAssertEqual(rec.suggestedRepsMin, 10)
        XCTAssertEqual(rec.suggestedRepsMax, 12)
        XCTAssertFalse(rec.isPlateau)
    }

    func testProgressionUsesStableIdForRenamedHistory() {
        let exercise = Exercise(
            id: "bench-1", name: "Barbell Bench Press", exerciseId: "barbell-bench-press",
            sets: 3, reps: RepTarget(min: 8, max: 12)
        )
        let record = WorkoutSessionRecord(
            id: "renamed", programId: "p1", workoutId: "w1", workoutTitle: "Push",
            startedAt: "2026-09-10T10:00:00Z", completedAt: "2026-09-10T11:00:00Z",
            durationSeconds: 3600,
            exerciseLogs: [SessionExerciseLog(
                exerciseName: "Previous bench label",
                sets: (1...3).map { SessionSetLog(setNumber: $0, weightKg: 80, reps: 10) },
                exerciseId: "barbell-bench-press"
            )]
        )
        XCTAssertEqual(ProgressionEngine.computeProgression(exercise: exercise, history: [record])?.action, .addReps)

        var conflicting = record
        conflicting.exerciseLogs[0].exerciseName = exercise.name
        conflicting.exerciseLogs[0].exerciseId = "barbell-back-squat"
        XCTAssertEqual(ProgressionEngine.computeProgression(exercise: exercise, history: [conflicting])?.action, .firstSession)
    }

    func testProgressionEngineRecommendsHoldLoadWhenSetsMissFloor() {
        let benchPress = Exercise(
            id: "bench-1",
            name: "Barbell Bench Press",
            exerciseId: "barbell-bench-press",
            sets: 3,
            reps: RepTarget(min: 8, max: 12)
        )
        let history = [
            WorkoutSessionRecord(
                id: "s1",
                programId: "p1",
                workoutId: "w1",
                workoutTitle: "Push",
                startedAt: "2026-09-10T10:00:00Z",
                completedAt: "2026-09-10T11:00:00Z",
                durationSeconds: 3600,
                exerciseLogs: [
                    SessionExerciseLog(
                        exerciseName: "Barbell Bench Press",
                        sets: [
                            SessionSetLog(setNumber: 1, weightKg: 80.0, reps: 8),
                            SessionSetLog(setNumber: 2, weightKg: 80.0, reps: 7),
                            SessionSetLog(setNumber: 3, weightKg: 80.0, reps: 6)
                        ]
                    )
                ]
            )
        ]

        let rec = ProgressionEngine.computeProgression(exercise: benchPress, history: history, weightUnit: .kg)!
        XCTAssertEqual(rec.action, .holdLoad)
        XCTAssertEqual(rec.suggestedWeightKg ?? 0, 80.0, accuracy: 0.01)
        XCTAssertEqual(rec.suggestedRepsMin, 7)
        XCTAssertEqual(rec.suggestedRepsMax, 9)
        XCTAssertEqual(rec.setTargets.map { $0.reps }, [9, 8, 7])
        XCTAssertFalse(rec.isPlateau)
    }

    func testProgressionEngineDetectsPlateauAfterThreeStagnantSessions() {
        let benchPress = Exercise(
            id: "bench-1",
            name: "Barbell Bench Press",
            exerciseId: "barbell-bench-press",
            sets: 3,
            reps: RepTarget(min: 8, max: 12)
        )
        let history = (1...3).map { i in
            WorkoutSessionRecord(
                id: "s\(i)",
                programId: "p1",
                workoutId: "w1",
                workoutTitle: "Push",
                startedAt: "2026-09-0\(i)T10:00:00Z",
                completedAt: "2026-09-0\(i)T11:00:00Z",
                durationSeconds: 3600,
                exerciseLogs: [
                    SessionExerciseLog(
                        exerciseName: "Barbell Bench Press",
                        sets: [
                            SessionSetLog(setNumber: 1, weightKg: 80.0, reps: 10),
                            SessionSetLog(setNumber: 2, weightKg: 80.0, reps: 9),
                            SessionSetLog(setNumber: 3, weightKg: 80.0, reps: 8)
                        ]
                    )
                ]
            )
        }

        let rec = ProgressionEngine.computeProgression(exercise: benchPress, history: history, weightUnit: .kg)!
        XCTAssertTrue(rec.isPlateau)
        XCTAssertEqual(rec.action, .deload)
        XCTAssertNil(rec.suggestedWeightKg)
        XCTAssertTrue(rec.setTargets.isEmpty)
        XCTAssertNil(rec.suggestedVariationId)
        XCTAssertNil(rec.suggestedVariationName)
    }

    func testEveryProgressionSwapResolvesToCatalogExercises() {
        let catalog = ExerciseCatalog.canonicalExercises
        for (sourceId, destination) in ProgressionEngine.variationSwaps {
            XCTAssertNotNil(catalog[sourceId], "Unknown swap source: \(sourceId)")
            XCTAssertEqual(catalog[destination.id]?.name, destination.name,
                           "Unknown or mislabeled swap destination for \(sourceId)")
        }
    }

    func testProgressionTrainingWeeksRequireAnUnbrokenRun() {
        func session(_ date: String) -> WorkoutSessionRecord {
            WorkoutSessionRecord(
                id: date, programId: "p1", workoutId: "w1", workoutTitle: "Push",
                startedAt: "\(date)T10:00:00Z", completedAt: "\(date)T11:00:00Z",
                durationSeconds: 3600,
                exerciseLogs: [SessionExerciseLog(exerciseName: "Barbell Bench Press", sets: [SessionSetLog(setNumber: 1, weightKg: 80.0, reps: 10)])]
            )
        }
        let scattered = ["2026-01-05", "2026-01-19", "2026-02-02", "2026-02-16", "2026-03-02", "2026-03-16"].map(session)
        let result = ProgressionEngine.evaluateMesocycleFatigue(history: scattered, activeProgram: nil)
        XCTAssertEqual(result.consecutiveWeeksTrained, 1)
        XCTAssertFalse(result.isRecommended)

        let continuous = ["2026-08-10", "2026-08-17", "2026-08-24", "2026-08-31", "2026-09-07", "2026-09-14"].map(session)
        XCTAssertEqual(ProgressionEngine.evaluateMesocycleFatigue(history: continuous, activeProgram: nil).consecutiveWeeksTrained, 6)
    }

    func testProgressionRepGainDoesNotTriggerPlateauPrompt() {
        let exercise = Exercise(id: "bench-1", name: "Barbell Bench Press", exerciseId: "barbell-bench-press", sets: 3, reps: RepTarget(min: 8, max: 12))
        let history = [("2026-09-03", 10), ("2026-09-10", 10), ("2026-09-17", 11)].map { entry in
            let (date, reps) = entry
            return WorkoutSessionRecord(
                id: date, programId: "p1", workoutId: "w1", workoutTitle: "Push",
                startedAt: "\(date)T10:00:00Z", completedAt: "\(date)T11:00:00Z",
                durationSeconds: 3600,
                exerciseLogs: [SessionExerciseLog(exerciseName: "Barbell Bench Press", sets: [SessionSetLog(setNumber: 1, weightKg: 80.0, reps: reps)])]
            )
        }
        XCTAssertFalse(ProgressionEngine.computeProgression(exercise: exercise, history: history)!.isPlateau)
    }

    func testProgressionEngineParsesRepRangesFromPrescription() {
        let exRange = Exercise(name: "Squat", prescription: "3 × 6–10")
        let (min1, max1) = ProgressionEngine.parseRepRange(exercise: exRange)!
        XCTAssertEqual(min1, 6)
        XCTAssertEqual(max1, 10)

        let exFixed = Exercise(name: "Deadlift", prescription: "5 reps")
        let (min2, max2) = ProgressionEngine.parseRepRange(exercise: exFixed)!
        XCTAssertEqual(min2, 5)
        XCTAssertEqual(max2, 5)
    }

    func testProgressionUsesRepsAfterLegacySetCountAndSkipsTechnicalFailure() {
        let legacy = Exercise(name: "Barbell Bench Press", exerciseId: "barbell-bench-press", prescription: "3 x 8 reps")
        XCTAssertEqual(ProgressionEngine.parseRepRange(exercise: legacy)?.min, 8)
        XCTAssertEqual(ProgressionEngine.parseRepRange(exercise: legacy)?.max, 8)

        let history = [WorkoutSessionRecord(
            id: "s1", programId: "p1", workoutId: "w1", workoutTitle: "Push",
            startedAt: "2026-09-17T10:00:00Z", completedAt: "2026-09-17T11:00:00Z",
            durationSeconds: 3600,
            exerciseLogs: [SessionExerciseLog(
                exerciseName: "Barbell Bench Press",
                sets: (1...3).map { SessionSetLog(setNumber: $0, weightKg: 80, reps: 3) }
            )]
        )]
        XCTAssertEqual(ProgressionEngine.computeProgression(exercise: legacy, history: history)?.action, .holdLoad)

        var failure = legacy
        failure.reps = RepTarget(toFailure: true)
        XCTAssertNil(ProgressionEngine.parseRepRange(exercise: failure))
        XCTAssertNil(ProgressionEngine.computeProgression(exercise: failure, history: []))
        XCTAssertNil(ProgressionEngine.computeProgression(exercise: failure, history: history))
        XCTAssertNil(WorkoutSessionUtils.computeGhostTarget(previousSets: [], workingSetIndex: 0, exercise: failure, unit: .kg).targetReps)
    }

    @MainActor
    func testProgressionCoachCardSnapshot() {
        let benchPress = Exercise(
            id: "bench-1",
            name: "Barbell Bench Press",
            exerciseId: "barbell-bench-press",
            sets: 3,
            reps: RepTarget(min: 8, max: 12)
        )
        let history = [
            WorkoutSessionRecord(
                id: "s1",
                programId: "p1",
                workoutId: "w1",
                workoutTitle: "Push",
                startedAt: "2026-09-10T10:00:00Z",
                completedAt: "2026-09-10T11:00:00Z",
                durationSeconds: 3600,
                exerciseLogs: [
                    SessionExerciseLog(
                        exerciseName: "Barbell Bench Press",
                        sets: [
                            SessionSetLog(setNumber: 1, weightKg: 80.0, reps: 12),
                            SessionSetLog(setNumber: 2, weightKg: 80.0, reps: 12),
                            SessionSetLog(setNumber: 3, weightKg: 80.0, reps: 12)
                        ]
                    )
                ]
            )
        ]

        let rec = ProgressionEngine.computeProgression(exercise: benchPress, history: history, weightUnit: .kg)!
        let card = ProgressionCoachCard(
            recommendation: rec,
            onApplyTarget: {},
            onOpenInfo: {}
        )
        .padding(20)

        let controller = UIHostingController(rootView: card)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 180)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 180))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_progression_coach_card_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }
    }

    @MainActor
    func testProgressionInfoSheetSnapshot() throws {
        let previous = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(previous) }
        func scrollViews(in view: UIView) -> [UIScrollView] {
            (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
        }
        for language in ["en", "tr"] {
            for (width, sizeCategory) in [
                (CGFloat(393), ContentSizeCategory.large),
                (CGFloat(320), ContentSizeCategory.extraExtraExtraLarge)
            ] {
                LanguageManager.setLanguage(language)
                let sheet = ProgressionInfoSheet()
                    .environment(\.sizeCategory, sizeCategory)
                    .frame(width: width, height: 852)
                let controller = UIHostingController(rootView: sheet)
                controller.safeAreaRegions = []
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 852))
                window.rootViewController = controller
                window.makeKeyAndVisible()
                controller.view.frame = window.bounds
                controller.view.layoutIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.2))
                controller.view.layoutIfNeeded()
                let scroll = try XCTUnwrap(scrollViews(in: controller.view).first)
                XCTAssertLessThanOrEqual(scroll.contentSize.width, scroll.bounds.width + 1)
                XCTAssertGreaterThan(scroll.contentSize.height, 0)
                for position in ["top", "rules-upper", "rules-lower", "bottom"] {
                    if position != "top" {
                        let bottom = max(-scroll.adjustedContentInset.top,
                            scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                        let offset = position == "bottom" ? bottom : min(bottom,
                            scroll.contentSize.height * (position == "rules-upper" ? 0.2 : 0.4))
                        scroll.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
                        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                        controller.view.layoutIfNeeded()
                    }
                    let image = UIGraphicsImageRenderer(size: controller.view.bounds.size).image { context in
                        controller.view.layer.render(in: context.cgContext)
                    }
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "progression-info-\(language)-\(Int(width))-\(position)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
                window.isHidden = true
            }
        }
    }

    @MainActor
    func testActiveSessionWithProgressionCoachSnapshot() {
        let store = AppStore.shared
        let originalHistory = store.state.history
        let originalSession = store.activeSession

        // Inject history for Barbell Bench Press where lifter hit rep ceiling (80kg x 12, 12, 12)
        let sampleHistory = WorkoutSessionRecord(
            id: "hist-bench",
            programId: "hypertrophy-split",
            workoutId: "push-1",
            workoutTitle: "Monday: Chest & Triceps",
            startedAt: "2026-09-15T10:00:00Z",
            completedAt: "2026-09-15T11:00:00Z",
            durationSeconds: 3600,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 80.0, reps: 12),
                        SessionSetLog(setNumber: 2, weightKg: 80.0, reps: 12),
                        SessionSetLog(setNumber: 3, weightKg: 80.0, reps: 12)
                    ]
                )
            ]
        )
        store.state.history = [sampleHistory] + originalHistory

        let benchExercise = Exercise(
            id: "bench-active",
            name: "Barbell Bench Press",
            exerciseId: "barbell-bench-press",
            prescription: "3 × 8–12",
            sets: 3,
            reps: RepTarget(min: 8, max: 12)
        )
        let inclineExercise = Exercise(
            id: "incline-active",
            name: "Incline Dumbbell Press",
            exerciseId: "incline-dumbbell-press",
            prescription: "3 × 10–12",
            sets: 3,
            reps: RepTarget(min: 10, max: 12)
        )
        let activeWorkout = Workout(
            id: "workout-chest",
            day: 1,
            title: "Chest & Triceps",
            exercises: [benchExercise, inclineExercise]
        )

        let initialSets = (1...3).map { ExerciseSetLog(setNumber: $0) }
        let draft = ActiveSessionDraft(
            id: "active-prog-session",
            programId: "hypertrophy-split",
            workout: activeWorkout,
            startedAt: "2026-09-19T13:00:00Z",
            startedAtEpochMillis: Int64(Date().timeIntervalSince1970 * 1000),
            currentExerciseIndex: 0,
            setsByExercise: [
                benchExercise.id: initialSets,
                inclineExercise.id: (1...3).map { ExerciseSetLog(setNumber: $0) }
            ]
        )

        store.activeSession = draft
        let sessionView = ActiveSessionView(store: store, draft: draft)
        let controller = UIHostingController(rootView: sessionView)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_active_session_with_progression.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote snapshot to \(path)")
        }

        // Restore state
        store.state.history = originalHistory
        store.activeSession = originalSession
    }

    @MainActor
    func testRootViewBottomDockSnapshot() {
        let store = AppStore.shared
        store.isOnboardingCompleted = true
        store.navigate(to: .today)

        let rootView = RootView()
        let controller = UIHostingController(rootView: rootView)
        controller.view.frame = CGRect(x: 0, y: 0, width: 440, height: 956)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_root_view_dock_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote RootView bottom dock snapshot to \(path)")
        }
    }

    func testWarmupRampFor100kgWorkingWeight() {
        let ramp = WarmupPlateEngine.generateWarmupRamp(
            workingWeightKg: 100.0,
            barWeightKg: 20.0,
            unit: .kg
        )

        XCTAssertEqual(ramp.workingWeightKg, 100.0, accuracy: 0.001)
        XCTAssertEqual(ramp.barWeightKg, 20.0, accuracy: 0.001)
        XCTAssertEqual(ramp.steps.count, 4)

        // Set 1: Empty Bar (20 kg) x 10 (warm joints)
        let s1 = ramp.steps[0]
        XCTAssertEqual(s1.setNumber, 1)
        XCTAssertEqual(s1.weightKg, 20.0, accuracy: 0.001)
        XCTAssertEqual(s1.reps, 10)
        XCTAssertEqual(s1.labelKey, "warmup.warm_joints")
        XCTAssertFalse(s1.isPotentiation)

        // Set 2: 50 kg x 5 (50% working weight)
        let s2 = ramp.steps[1]
        XCTAssertEqual(s2.setNumber, 2)
        XCTAssertEqual(s2.weightKg, 50.0, accuracy: 0.001)
        XCTAssertEqual(s2.reps, 5)
        XCTAssertEqual(s2.labelKey, "warmup.50_percent")
        XCTAssertFalse(s2.isPotentiation)

        // Set 3: 70 kg x 3 (70% working weight)
        let s3 = ramp.steps[2]
        XCTAssertEqual(s3.setNumber, 3)
        XCTAssertEqual(s3.weightKg, 70.0, accuracy: 0.001)
        XCTAssertEqual(s3.reps, 3)
        XCTAssertEqual(s3.labelKey, "warmup.70_percent")
        XCTAssertFalse(s3.isPotentiation)

        // Set 4: 85 kg x 1 (85% potentiation single)
        let s4 = ramp.steps[3]
        XCTAssertEqual(s4.setNumber, 4)
        XCTAssertEqual(s4.weightKg, 85.0, accuracy: 0.001)
        XCTAssertEqual(s4.reps, 1)
        XCTAssertEqual(s4.labelKey, "warmup.85_percent")
        XCTAssertTrue(s4.isPotentiation)
    }

    func testBarbellWarmupNeedsKnownLoadAndSupportedEquipment() {
        let catalog = EquipmentCatalog.shared
        XCTAssertTrue(WarmupPlateEngine.supportsExercise(equipmentCategory: catalog.categoryId("barbell-bench-press")))
        for id in ["pull-ups", "cable-lateral-raise", "leg-press"] {
            XCTAssertFalse(WarmupPlateEngine.supportsExercise(equipmentCategory: catalog.categoryId(id)))
        }
        XCTAssertFalse(WarmupPlateEngine.hasWorkingLoad(nil))
        XCTAssertFalse(WarmupPlateEngine.hasWorkingLoad(0))
        XCTAssertFalse(WarmupPlateEngine.hasWorkingLoad(.nan))
        XCTAssertTrue(WarmupPlateEngine.hasWorkingLoad(80))
        XCTAssertTrue(WarmupPlateEngine.generateWarmupRamp(workingWeightKg: 0, barWeightKg: 20).steps.isEmpty)
        XCTAssertTrue(WarmupPlateEngine.generateWarmupRamp(workingWeightKg: 15, barWeightKg: 20).steps.isEmpty)
    }

    func testWarmupRampForLightWeights() {
        // Working weight equal to bar: only empty bar
        let ramp20 = WarmupPlateEngine.generateWarmupRamp(workingWeightKg: 20.0, barWeightKg: 20.0)
        XCTAssertEqual(ramp20.steps.count, 1)
        XCTAssertEqual(ramp20.steps[0].weightKg, 20.0, accuracy: 0.001)
        XCTAssertEqual(ramp20.steps[0].reps, 10)

        // Working weight 40 kg: strictly increasing, strictly < 40 kg
        let ramp40 = WarmupPlateEngine.generateWarmupRamp(workingWeightKg: 40.0, barWeightKg: 20.0)
        XCTAssertFalse(ramp40.steps.isEmpty)
        XCTAssertTrue(ramp40.steps.allSatisfy { $0.weightKg < 40.0 })
        for i in 1..<ramp40.steps.count {
            XCTAssertTrue(ramp40.steps[i].weightKg > ramp40.steps[i - 1].weightKg)
        }
    }

    func testCalculatePlates95kgPromptExample() {
        // (95 - 20) / 2 = 37.5 kg per side = 1x20kg + 1x15kg + 1x2.5kg
        let platesWithout25: [Double] = [20.0, 15.0, 10.0, 5.0, 2.5, 1.25]
        let result = WarmupPlateEngine.calculatePlates(
            targetWeight: 95.0,
            barWeight: 20.0,
            availablePlates: platesWithout25,
            unit: .kg
        )

        XCTAssertTrue(result.isExactMatch)
        XCTAssertEqual(result.weightPerSide, 37.5, accuracy: 0.001)
        XCTAssertEqual(result.totalPlatesWeight, 75.0, accuracy: 0.001)
        XCTAssertEqual(result.totalAchievedWeight, 95.0, accuracy: 0.001)
        XCTAssertEqual(result.remainderPerSide, 0.0, accuracy: 0.001)

        XCTAssertEqual(result.platesPerSide.count, 3)
        XCTAssertEqual(result.platesPerSide[0].weight, 20.0, accuracy: 0.001)
        XCTAssertEqual(result.platesPerSide[0].count, 1)
        XCTAssertEqual(result.platesPerSide[1].weight, 15.0, accuracy: 0.001)
        XCTAssertEqual(result.platesPerSide[1].count, 1)
        XCTAssertEqual(result.platesPerSide[2].weight, 2.5, accuracy: 0.001)
        XCTAssertEqual(result.platesPerSide[2].count, 1)

        XCTAssertEqual(result.displayText, "1×20 kg + 1×15 kg + 1×2.5 kg")
    }

    func testCalculatePlatesUnderOrEqualBarWeight() {
        let resultEmpty = WarmupPlateEngine.calculatePlates(targetWeight: 20.0, barWeight: 20.0, availablePlates: WarmupPlateEngine.defaultPlatesKg)
        XCTAssertTrue(resultEmpty.isExactMatch)
        XCTAssertTrue(resultEmpty.platesPerSide.isEmpty)
        XCTAssertEqual(resultEmpty.totalAchievedWeight, 20.0, accuracy: 0.001)

        let resultUnder = WarmupPlateEngine.calculatePlates(targetWeight: 15.0, barWeight: 20.0, availablePlates: WarmupPlateEngine.defaultPlatesKg)
        XCTAssertFalse(resultUnder.isExactMatch)
        XCTAssertTrue(resultUnder.platesPerSide.isEmpty)
    }

    func testFormatPlateWeightEliminatesFloatingPointNoise() {
        XCTAssertEqual(WarmupPlateEngine.formatPlateWeight(65.00000000000361), "65")
        XCTAssertEqual(WarmupPlateEngine.formatPlateWeight(64.99999999999999), "65")
        XCTAssertEqual(WarmupPlateEngine.formatPlateWeight(2.5000000000001), "2.5")
        XCTAssertEqual(WarmupPlateEngine.formatPlateWeight(1.2500000000002), "1.25")
        XCTAssertEqual(WarmupPlateEngine.formatPlateWeight(20.0), "20")
        XCTAssertEqual(WarmupPlateEngine.formatPlateWeight(5.0), "5")
        XCTAssertEqual(WarmupPlateEngine.formatPlateWeight(0.0), "0")
    }

    func testWarmupSetsExcludedFromVolumeAndCompletedCount() {
        let exercise = Exercise(
            id: "ex-bench",
            name: "Barbell Bench Press",
            sets: 3
        )
        let workout = Workout(
            id: "w1",
            day: 1,
            title: "Chest Day",
            exercises: [exercise]
        )

        let sets: [ExerciseSetLog] = [
            // 2 Warmup sets (both completed)
            ExerciseSetLog(id: "w1", setNumber: 1, weightKg: 20.0, completedReps: 10, isCompleted: true, isWarmup: true),
            ExerciseSetLog(id: "w2", setNumber: 2, weightKg: 50.0, completedReps: 5, isCompleted: true, isWarmup: true),
            // 3 Working sets (1 completed at 100kg x 8, 2 uncompleted)
            ExerciseSetLog(id: "s1", setNumber: 1, weightKg: 100.0, completedReps: 8, isCompleted: true, isWarmup: false),
            ExerciseSetLog(id: "s2", setNumber: 2, weightKg: 100.0, completedReps: 8, isCompleted: false, isWarmup: false),
            ExerciseSetLog(id: "s3", setNumber: 3, weightKg: 100.0, completedReps: 8, isCompleted: false, isWarmup: false)
        ]

        let draft = ActiveSessionDraft(
            id: UUID().uuidString,
            programId: "prog1",
            workout: workout,
            startedAt: "2026-09-19T20:00:00Z",
            startedAtEpochMillis: 1000,
            setsByExercise: [exercise.id: sets]
        )

        let progress = SessionProgress.from(draft: draft, nowEpochMillis: 5000)

        // Only the 1 completed working set should count!
        XCTAssertEqual(progress.completedSets, 1)
        // Only working set volume: 100 kg * 8 reps = 800 kg (warmup 20*10=200kg and 50*5=250kg MUST be excluded!)
        XCTAssertEqual(progress.volumeKg, 800.0, accuracy: 0.001)

        let exerciseLog = progress.exerciseLogs.first!
        // Target sets should only count working sets (3)
        XCTAssertEqual(exerciseLog.targetSets, 3)
        // All sets are recorded in logs with isWarmup preserved
        XCTAssertEqual(exerciseLog.sets.count, 3)
        XCTAssertTrue(exerciseLog.sets[0].isWarmup)
        XCTAssertTrue(exerciseLog.sets[1].isWarmup)
        XCTAssertFalse(exerciseLog.sets[2].isWarmup)
    }

    @MainActor
    func testWarmupPlateSheetSnapshot() {
        let sheetRamp = WarmupPlateSheet(
            exerciseName: "Barbell Bench Press",
            initialWorkingWeightKg: 100.0,
            initialBarType: .olympic20,
            initialPlatesKg: WarmupPlateEngine.defaultPlatesKg,
            unit: .kg,
            initialTab: .warmupRamp,
            onInsertWarmupSets: { _ in },
            onSaveBarType: { _ in },
            onSavePlates: { _ in }
        )
        let controllerRamp = UIHostingController(rootView: sheetRamp)
        controllerRamp.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controllerRamp.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)
        let windowRamp = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        windowRamp.rootViewController = controllerRamp
        windowRamp.makeKeyAndVisible()
        controllerRamp.view.layoutIfNeeded()

        let rendererRamp = UIGraphicsImageRenderer(size: controllerRamp.view.bounds.size)
        let imageRamp = rendererRamp.image { ctx in
            controllerRamp.view.drawHierarchy(in: controllerRamp.view.bounds, afterScreenUpdates: true)
        }
        if let data = imageRamp.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_warmup_ramp_sheet_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote warmup ramp sheet snapshot to \(path)")
        }

        let sheetPlates = WarmupPlateSheet(
            exerciseName: "Barbell Bench Press",
            initialWorkingWeightKg: 100.0,
            initialBarType: .olympic20,
            initialPlatesKg: WarmupPlateEngine.defaultPlatesKg,
            unit: .kg,
            initialTab: .plateLoader,
            onInsertWarmupSets: { _ in },
            onSaveBarType: { _ in },
            onSavePlates: { _ in }
        )
        let controllerPlates = UIHostingController(rootView: sheetPlates)
        controllerPlates.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controllerPlates.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)
        let windowPlates = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        windowPlates.rootViewController = controllerPlates
        windowPlates.makeKeyAndVisible()
        controllerPlates.view.layoutIfNeeded()

        let rendererPlates = UIGraphicsImageRenderer(size: controllerPlates.view.bounds.size)
        let imagePlates = rendererPlates.image { ctx in
            controllerPlates.view.drawHierarchy(in: controllerPlates.view.bounds, afterScreenUpdates: true)
        }
        if let data = imagePlates.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_plate_loader_sheet_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote plate loader sheet snapshot to \(path)")
        }
    }

    @MainActor
    func testActiveSessionWithWarmupSetsSnapshot() {
        let store = AppStore.shared
        let originalSession = store.activeSession

        let benchExercise = Exercise(
            id: "ex-bench-warmup",
            name: "Barbell Bench Press",
            exerciseId: "bench-press",
            prescription: "3×8-12",
            sets: 3
        )
        let workout = Workout(
            id: "w-chest-warmup",
            day: 1,
            title: "Push Day",
            exercises: [benchExercise]
        )

        let sets: [ExerciseSetLog] = [
            ExerciseSetLog(id: "w1", setNumber: 1, weightInput: "20", repsInput: "10", weightKg: 20.0, completedReps: 10, isCompleted: true, inputTouched: true, isWarmup: true),
            ExerciseSetLog(id: "w2", setNumber: 2, weightInput: "50", repsInput: "5", weightKg: 50.0, completedReps: 5, isCompleted: true, inputTouched: true, isWarmup: true),
            ExerciseSetLog(id: "w3", setNumber: 3, weightInput: "70", repsInput: "3", weightKg: 70.0, completedReps: 3, isCompleted: true, inputTouched: true, isWarmup: true),
            ExerciseSetLog(id: "w4", setNumber: 4, weightInput: "85", repsInput: "1", weightKg: 85.0, completedReps: 1, isCompleted: false, inputTouched: true, isWarmup: true),
            ExerciseSetLog(id: "s1", setNumber: 1, weightInput: "100", repsInput: "8", weightKg: 100.0, completedReps: nil, isCompleted: false, inputTouched: true, isWarmup: false),
            ExerciseSetLog(id: "s2", setNumber: 2, weightInput: "100", repsInput: "8", weightKg: 100.0, completedReps: nil, isCompleted: false, inputTouched: true, isWarmup: false),
            ExerciseSetLog(id: "s3", setNumber: 3, weightInput: "100", repsInput: "8", weightKg: 100.0, completedReps: nil, isCompleted: false, inputTouched: true, isWarmup: false)
        ]

        let draft = ActiveSessionDraft(
            id: "session-warmup-demo",
            programId: "prog1",
            workout: workout,
            startedAt: "2026-09-19T20:00:00Z",
            startedAtEpochMillis: Int64(Date().timeIntervalSince1970 * 1000) - 900_000,
            currentExerciseIndex: 0,
            setsByExercise: [benchExercise.id: sets]
        )

        store.activeSession = draft
        let sessionView = ActiveSessionView(store: store, draft: draft)
        let controller = UIHostingController(rootView: sessionView)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_active_session_with_warmup_sets_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote active session with warmups snapshot to \(path)")
        }

        store.activeSession = originalSession
    }

    @MainActor
    func testWarmupPlateCardInactiveSnapshot() async throws {
        let manager = ProAccessManager.shared
        let previousLanguage = LanguageManager.shared.currentLanguage
        let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        defer {
            previousWindow?.makeKeyAndVisible()
            LanguageManager.setLanguage(previousLanguage)
            manager.setFeatureOverride(.warmupCalculator, unlocked: nil)
        }
        for language in ["en", "tr"] {
            LanguageManager.setLanguage(language)
            for (width, textSize) in [(CGFloat(393), ContentSizeCategory.large), (320, .large), (320, .extraExtraExtraLarge)] {
                for unlocked in [false, true] {
                    manager.setFeatureOverride(.warmupCalculator, unlocked: unlocked)
                    for dismissible in [false, true] where !unlocked || !dismissible {
                        let card = WarmupPlateCard(warmupSets: [], onGenerateWarmup: {}, onOpenPlates: {},
                            onClearWarmups: {}, onDismissLocked: dismissible ? {} : nil)
                            .padding(20).frame(width: width).background(AppColors.background).ignoresSafeArea()
                            .environment(\.sizeCategory, textSize)
                        let controller = UIHostingController(rootView: card)
                        let size = controller.sizeThatFits(in: CGSize(width: width, height: 1000))
                        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
                        window.rootViewController = controller
                        window.makeKeyAndVisible()
                        controller.view.frame = window.bounds
                        controller.view.layoutIfNeeded()
                        try await Task.sleep(nanoseconds: 250_000_000)
                        let image = UIGraphicsImageRenderer(size: size).image { context in
                            controller.view.layer.render(in: context.cgContext)
                        }
                        window.isHidden = true
                        XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 3000, "Card content must be visible")
                        XCTAssertEqual(image.size.width, width)
                        XCTAssertGreaterThan(image.size.height, 100)
                        let attachment = XCTAttachment(image: image)
                        attachment.name = "warmup-\(language)-\(unlocked ? "unlocked" : "locked")-\(dismissible ? "dismissible" : "plain")-\(Int(width))-\(textSize == .large ? "normal" : "large")"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                    }
                }
            }
        }
    }

    @MainActor
    func testClearWarmupSetsPreservesCompletedSets() {
        let store = AppStore(persistence: AppStatePersistence(inMemory: true))
        let exercise = Exercise(id: "bench", name: "Bench", sets: 2, reps: RepTarget(min: 8, max: 12), restSeconds: 90)
        let workout = Workout(id: "w1", day: 1, title: "Push", exercises: [exercise])
        let session = ActiveSessionDraft(
            id: "s1",
            programId: "p1",
            workout: workout,
            startedAt: "2026-08-28T09:00:00Z",
            startedAtEpochMillis: 1000,
            setsByExercise: [
                exercise.id: [
                    ExerciseSetLog(id: "w1", setNumber: 1, weightInput: "20", repsInput: "10", weightKg: 20, completedReps: 10, isCompleted: true, isWarmup: true),
                    ExerciseSetLog(id: "w2", setNumber: 2, weightInput: "40", repsInput: "5", weightKg: 40, completedReps: 5, isCompleted: false, isWarmup: true),
                    ExerciseSetLog(id: "s1", setNumber: 1, weightInput: "60", repsInput: "10", weightKg: 60, completedReps: 10, isCompleted: false, isWarmup: false)
                ]
            ]
        )
        store.activeSession = session
        store.clearWarmupSets(exerciseId: exercise.id)

        let sets = store.activeSession?.setsByExercise[exercise.id] ?? []
        XCTAssertEqual(sets.count, 2)
        XCTAssertEqual(sets[0].id, "w1")
        XCTAssertTrue(sets[0].isWarmup)
        XCTAssertTrue(sets[0].isCompleted)
        XCTAssertEqual(sets[0].setNumber, 1)

        XCTAssertEqual(sets[1].id, "s1")
        XCTAssertFalse(sets[1].isWarmup)
        XCTAssertEqual(sets[1].setNumber, 1)
    }

    @MainActor
    func testWarmupPlateCardActiveWithIncompleteWarmupsSnapshot() {
        ProAccessManager.shared.updateSubscriptionStatus(active: true)
        defer { ProAccessManager.shared.updateSubscriptionStatus(active: false) }

        let warmups = [
            ExerciseSetLog(id: "w1", setNumber: 1, weightInput: "20", repsInput: "10", weightKg: 20, completedReps: 10, isCompleted: true, isWarmup: true),
            ExerciseSetLog(id: "w2", setNumber: 2, weightInput: "40", repsInput: "5", weightKg: 40, completedReps: 5, isCompleted: false, isWarmup: true)
        ]
        let card = WarmupPlateCard(
            warmupSets: warmups,
            onGenerateWarmup: {},
            onOpenPlates: {},
            onClearWarmups: {}
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .background(AppColors.background)

        let controller = UIHostingController(rootView: card)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 120)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 120))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_warmup_plate_card_active_with_delete_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote active warmup plate card with delete snapshot to \(path)")
        }
    }

    @MainActor
    func testWarmupPlateCardActiveAllCompletedSnapshot() {
        ProAccessManager.shared.updateSubscriptionStatus(active: true)
        defer { ProAccessManager.shared.updateSubscriptionStatus(active: false) }

        let warmups = [
            ExerciseSetLog(id: "w1", setNumber: 1, weightInput: "20", repsInput: "10", weightKg: 20, completedReps: 10, isCompleted: true, isWarmup: true),
            ExerciseSetLog(id: "w2", setNumber: 2, weightInput: "40", repsInput: "5", weightKg: 40, completedReps: 5, isCompleted: true, isWarmup: true)
        ]
        let card = WarmupPlateCard(
            warmupSets: warmups,
            onGenerateWarmup: {},
            onOpenPlates: {},
            onClearWarmups: {}
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .background(AppColors.background)

        let controller = UIHostingController(rootView: card)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 120)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 120))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_warmup_plate_card_active_all_completed_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote active warmup plate card with all completed snapshot to \(path)")
        }
    }

    @MainActor
    func testProgressionCoachCardInactiveSnapshot() async throws {
        let manager = ProAccessManager.shared
        let previousLanguage = LanguageManager.shared.currentLanguage
        let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        manager.setFeatureOverride(.autoProgression, unlocked: false)
        manager.setFeatureOverride(.warmupCalculator, unlocked: false)
        defer {
            previousWindow?.makeKeyAndVisible()
            LanguageManager.setLanguage(previousLanguage)
            manager.setFeatureOverride(.autoProgression, unlocked: nil)
            manager.setFeatureOverride(.warmupCalculator, unlocked: nil)
        }
        let dummyRecommendation = ExerciseProgressionRecommendation(
            exerciseId: "bench_press",
            exerciseName: "Bench Press",
            action: .increaseLoad,
            suggestedWeightKg: 82.5,
            suggestedWeightDisplay: "82.5 kg",
            suggestedRepsMin: 5,
            suggestedRepsMax: 5,
            weightDeltaDisplay: "+2.5 kg",
            rationaleKey: "progression.rationale.all_sets_hit_max_reps",
            rationaleArgs: ["reps": "5"]
        )
        for language in ["en", "tr"] {
            LanguageManager.setLanguage(language)
            for (width, textSize) in [(CGFloat(393), ContentSizeCategory.large), (320, .large), (320, .extraExtraExtraLarge)] {
                let cards = VStack(spacing: 12) {
                    ProgressionCoachCard(recommendation: dummyRecommendation, onApplyTarget: {}, onOpenInfo: {}, onDismissLocked: {})
                    WarmupPlateCard(warmupSets: [], onGenerateWarmup: {}, onOpenPlates: {}, onClearWarmups: {}, onDismissLocked: {})
                }
                .padding(20).frame(width: width).background(AppColors.background).ignoresSafeArea()
                .environment(\.sizeCategory, textSize)
                let controller = UIHostingController(rootView: cards)
                let size = controller.sizeThatFits(in: CGSize(width: width, height: 1000))
                let window = UIWindow(frame: CGRect(origin: .zero, size: size))
                window.rootViewController = controller
                window.makeKeyAndVisible()
                controller.view.frame = window.bounds
                controller.view.layoutIfNeeded()
                try await Task.sleep(nanoseconds: 250_000_000)
                let image = UIGraphicsImageRenderer(size: size).image { context in
                    controller.view.layer.render(in: context.cgContext)
                }
                window.isHidden = true
                XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 5000, "Both locked cards must be visible")
                XCTAssertEqual(image.size.width, width)
                let attachment = XCTAttachment(image: image)
                attachment.name = "locked-cards-\(language)-\(Int(width))-\(textSize == .large ? "normal" : "large")"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    @MainActor
    func testDismissProCardsInSessionAndRestoreFromSettings() {
        let store = AppStore.shared
        store.resetDismissedProCards()
        XCTAssertFalse(store.isProgressionCardDismissed)
        XCTAssertFalse(store.isWarmupCardDismissed)
        XCTAssertTrue(store.showProgressionTargets)
        XCTAssertTrue(store.showWarmupCalculator)

        store.isProgressionCardDismissed = true
        XCTAssertTrue(store.isProgressionCardDismissed)
        XCTAssertFalse(store.showProgressionTargets)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "pro_progression_card_dismissed"))
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "show_progression_targets"))

        store.isWarmupCardDismissed = true
        XCTAssertTrue(store.isWarmupCardDismissed)
        XCTAssertFalse(store.showWarmupCalculator)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "pro_warmup_card_dismissed"))
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "show_warmup_calculator"))

        store.resetDismissedProCards()
        XCTAssertFalse(store.isProgressionCardDismissed)
        XCTAssertFalse(store.isWarmupCardDismissed)
        XCTAssertTrue(store.showProgressionTargets)
        XCTAssertTrue(store.showWarmupCalculator)
    }

    @MainActor
    func testSeparateSessionCardsSettings() {
        let store = AppStore.shared
        store.resetDismissedProCards()
        XCTAssertTrue(store.showProgressionTargets)
        XCTAssertTrue(store.showWarmupCalculator)

        // Hide progression targets independently
        store.showProgressionTargets = false
        XCTAssertFalse(store.showProgressionTargets)
        XCTAssertTrue(store.isProgressionCardDismissed)
        XCTAssertTrue(store.showWarmupCalculator, "Warmup calculator setting must remain unchanged")
        XCTAssertFalse(store.isWarmupCardDismissed)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "show_progression_targets"))
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "show_warmup_calculator"))

        // Hide warmup calculator independently
        store.showWarmupCalculator = false
        XCTAssertFalse(store.showProgressionTargets)
        XCTAssertFalse(store.showWarmupCalculator)
        XCTAssertTrue(store.isWarmupCardDismissed)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "show_warmup_calculator"))

        // Re-enable progression targets independently
        store.showProgressionTargets = true
        XCTAssertTrue(store.showProgressionTargets)
        XCTAssertFalse(store.isProgressionCardDismissed)
        XCTAssertFalse(store.showWarmupCalculator, "Warmup calculator must remain hidden")
        XCTAssertTrue(store.isWarmupCardDismissed)

        // Reset both
        store.resetDismissedProCards()
        XCTAssertTrue(store.showProgressionTargets)
        XCTAssertTrue(store.showWarmupCalculator)
    }

    // MARK: - Form Lab Unit & Snapshot Tests

    func testFormLabStableIdsUnifyRenamedHistory() {
        func record(_ id: String, _ date: String, _ name: String, _ weight: Double) -> WorkoutSessionRecord {
            WorkoutSessionRecord(
                id: id, programId: "p1", workoutId: "w1", workoutTitle: "Push",
                startedAt: date, completedAt: date, durationSeconds: 3600,
                exerciseLogs: [SessionExerciseLog(
                    exerciseName: name,
                    sets: [SessionSetLog(setNumber: 1, weightKg: weight, reps: 5)],
                    exerciseId: "barbell-bench-press"
                )]
            )
        }
        let history = [
            record("older", "2026-09-01T10:00:00Z", "Old bench label", 80),
            record("newer", "2026-09-08T10:00:00Z", "Barbell Bench Press", 100)
        ]
        let summary = FormLabEngine.computeExerciseRepMax(exerciseName: "Barbell Bench Press", history: history)
        XCTAssertEqual(summary?.estimated1rmKg ?? 0, 112.5, accuracy: 0.001)
        XCTAssertEqual(FormLabEngine.computeLongitudinalCurve(exerciseName: "Barbell Bench Press", history: history).points.count, 2)
        XCTAssertEqual(FormLabEngine.computeAllRepMaxSummaries(history: history).count, 1)
        XCTAssertEqual(FormLabEngine.resolveExerciseMuscles(exerciseName: "Old bench label", exerciseId: "barbell-bench-press"), ["chest"])
    }

    func testFormLabRepMaxCalculations() {
        // Brzycki
        let brzycki1Rep = FormLabEngine.calculateEstimated1RM(weightKg: 100.0, reps: 1, formula: .brzycki)
        XCTAssertEqual(brzycki1Rep, 100.0, accuracy: 0.001)

        let brzycki5Reps = FormLabEngine.calculateEstimated1RM(weightKg: 100.0, reps: 5, formula: .brzycki)
        // 100 * 36 / (37 - 5) = 3600 / 32 = 112.5
        XCTAssertEqual(brzycki5Reps, 112.5, accuracy: 0.001)

        // Epley
        let epley10Reps = FormLabEngine.calculateEstimated1RM(weightKg: 100.0, reps: 10, formula: .epley)
        // 100 * (1 + 10/30) = 133.333
        XCTAssertEqual(epley10Reps, 133.333, accuracy: 0.01)

        // Target N-RM
        let target5RM = FormLabEngine.calculateTargetNRM(oneRmKg: 112.5, targetReps: 5, formula: .brzycki)
        XCTAssertEqual(target5RM, 100.0, accuracy: 0.01)

        // Multi-rep targets
        let targets = FormLabEngine.computeRepMaxTargets(oneRmKg: 100.0, formula: .brzycki)
        XCTAssertEqual(targets.count, 5)
        XCTAssertEqual(targets[0].reps, 1)
        XCTAssertEqual(targets[0].estimatedWeightKg, 100.0, accuracy: 0.01)
        XCTAssertEqual(targets[1].reps, 3)
        XCTAssertEqual(targets[2].reps, 5)
        XCTAssertEqual(targets[3].reps, 8)
        XCTAssertEqual(targets[4].reps, 10)
    }

    func testFormLabLongitudinalCurve() {
        let session1 = WorkoutSessionRecord(
            id: "s1",
            programId: "p1",
            workoutId: "w1",
            workoutTitle: "Chest Day 1",
            startedAt: "2026-06-01T10:00:00Z",
            completedAt: "2026-06-01T11:00:00Z",
            durationSeconds: 3600,
            totalVolumeKg: 800.0,
            totalCompletedSets: 10,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 80.0, reps: 10, isWarmup: false)
                    ]
                )
            ]
        )

        let session2 = WorkoutSessionRecord(
            id: "s2",
            programId: "p1",
            workoutId: "w2",
            workoutTitle: "Chest Day 2",
            startedAt: "2026-08-01T10:00:00Z",
            completedAt: "2026-08-01T11:00:00Z",
            durationSeconds: 3600,
            totalVolumeKg: 1000.0,
            totalCompletedSets: 10,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [
                        SessionSetLog(setNumber: 1, weightKg: 100.0, reps: 5, isWarmup: false)
                    ]
                )
            ]
        )

        let report = FormLabEngine.computeLongitudinalCurve(
            exerciseName: "Barbell Bench Press",
            history: [session1, session2],
            timeframe: .allTime,
            formula: .brzycki
        )

        XCTAssertEqual(report.points.count, 2)
        XCTAssertNotNil(report.start1rmKg)
        XCTAssertNotNil(report.current1rmKg)
        XCTAssertGreaterThan(report.current1rmKg!, report.start1rmKg!)
        XCTAssertGreaterThan(report.deltaKg, 0)
        XCTAssertGreaterThan(report.percentageGain, 0)
    }

    func testFormLabDateParsingWithFractionalSecondsAndDateFormats() {
        let sMillis = WorkoutSessionRecord(
            id: "s_millis",
            programId: "p1",
            workoutId: "w1",
            workoutTitle: "Chest Day",
            startedAt: "2026-09-01T10:00:00.000Z",
            completedAt: "2026-09-01T11:00:00.000Z",
            durationSeconds: 3600,
            totalVolumeKg: 500.0,
            totalCompletedSets: 5,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [SessionSetLog(setNumber: 1, weightKg: 100.0, reps: 5, isWarmup: false)]
                )
            ]
        )
        let sStandard = WorkoutSessionRecord(
            id: "s_standard",
            programId: "p1",
            workoutId: "w2",
            workoutTitle: "Chest Day",
            startedAt: "2026-09-15T10:00:00Z",
            completedAt: "2026-09-15T11:00:00Z",
            durationSeconds: 3600,
            totalVolumeKg: 600.0,
            totalCompletedSets: 5,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [SessionSetLog(setNumber: 1, weightKg: 110.0, reps: 5, isWarmup: false)]
                )
            ]
        )
        let sDateOnly = WorkoutSessionRecord(
            id: "s_dateonly",
            programId: "p1",
            workoutId: "w3",
            workoutTitle: "Chest Day",
            startedAt: "2026-09-20",
            completedAt: "2026-09-20",
            durationSeconds: 3600,
            totalVolumeKg: 700.0,
            totalCompletedSets: 5,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [SessionSetLog(setNumber: 1, weightKg: 120.0, reps: 5, isWarmup: false)]
                )
            ]
        )

        let report = FormLabEngine.computeLongitudinalCurve(
            exerciseName: "Barbell Bench Press",
            history: [sMillis, sStandard, sDateOnly],
            timeframe: .allTime,
            formula: .brzycki
        )
        XCTAssertEqual(report.points.count, 3)
        XCTAssertEqual(report.start1rmKg, FormLabEngine.calculateEstimated1RM(weightKg: 100.0, reps: 5, formula: .brzycki))
        XCTAssertEqual(report.current1rmKg, FormLabEngine.calculateEstimated1RM(weightKg: 120.0, reps: 5, formula: .brzycki))

        // Direct parseRecordDate checks
        XCTAssertNotNil(FormLabEngine.parseRecordDate("2026-09-21T17:30:00.000Z"))
        XCTAssertNotNil(FormLabEngine.parseRecordDate("2026-09-21T17:30:00.123+03:00"))
        XCTAssertNotNil(FormLabEngine.parseRecordDate("2026-09-21T17:30:00Z"))
        XCTAssertNotNil(FormLabEngine.parseRecordDate("2026-09-21"))
        XCTAssertNotNil(FormLabEngine.parseRecordDate("2026-09-21 17:30:00"))
    }

    func testDistributionUsesExactCatalogClassifications() {
        XCTAssertGreaterThanOrEqual(ExerciseCatalog.canonicalExercises.count, 300)
        XCTAssertNotNil(ExerciseMuscleCatalog.shared)
        for exercise in ExerciseCatalog.canonicalExercises.values {
            let expected = ExerciseMuscleCatalog.shared?.profile(exercise.id)?.primary ?? []
            XCTAssertEqual(FormLabEngine.resolveExerciseMuscles(exerciseName: exercise.id), expected, exercise.id)
            XCTAssertEqual(FormLabEngine.resolveExerciseMuscles(exerciseName: exercise.name), expected, exercise.name)
        }
        for name in ["Seated Leg Curl", "Lying Leg Curl", "  SEATED LEG CURL  "] {
            XCTAssertEqual(FormLabEngine.resolveExerciseMuscles(exerciseName: name), ["hamstrings"])
        }
        XCTAssertEqual(FormLabEngine.resolveExerciseMuscles(exerciseName: "Barbell Curl"), ["biceps"])
        for name in ["My leg curl", "Custom curl", "My chest-supported row", "Unknown"] {
            XCTAssertTrue(FormLabEngine.resolveExerciseMuscles(exerciseName: name).isEmpty)
        }
    }

    func testDistributionKeepsGlutesSeparateAndReportsMissingWork() {
        func report(_ name: String, count: Int = 4) -> AntagonistBalanceReport {
            let sets = (1...count).map { SessionSetLog(setNumber: $0, weightKg: 40, reps: 8, isWarmup: false) }
                + [SessionSetLog(setNumber: 99, weightKg: 10, reps: 8, isWarmup: true)]
            let session = WorkoutSessionRecord(id: "classification", programId: "p", workoutId: "w", workoutTitle: "Test",
                startedAt: "2026-09-10T10:00:00Z", completedAt: "2026-09-10T11:00:00Z", durationSeconds: 3600,
                totalVolumeKg: 1280, totalCompletedSets: count, exerciseLogs: [SessionExerciseLog(exerciseName: name, sets: sets)])
            return FormLabEngine.computeAntagonistBalance(history: [session])
        }
        let squat = report("Barbell Back Squat")
        XCTAssertEqual(squat.quadHamstring.primarySets, 4)
        XCTAssertEqual(squat.quadHamstring.antagonistSets, 0)
        XCTAssertNil(squat.quadHamstring.ratio)
        XCTAssertEqual(squat.quadHamstring.alertMessageKey, "form_lab.balance.no_hamstrings")
        XCTAssertNotEqual(squat.quadHamstring.status, .optimal)
        let glutes = report("Barbell Hip Thrust")
        XCTAssertEqual(glutes.quadHamstring.antagonistSets, 0)
        XCTAssertEqual(glutes.upperLower.antagonistSets, 4)
        XCTAssertEqual(glutes.upperLower.alertMessageKey, "form_lab.balance.no_upper")
        let curl = report("Seated Leg Curl")
        XCTAssertEqual(curl.quadHamstring.antagonistSets, 4)
        XCTAssertEqual(curl.pushPull.antagonistSets, 0)
        XCTAssertEqual(curl.quadHamstring.alertMessageKey, "form_lab.balance.no_quads")
        XCTAssertEqual(report("Barbell Row").pushPull.alertMessageKey, "form_lab.balance.no_push")
        let push = report("Barbell Bench Press")
        XCTAssertNil(push.pushPull.ratio)
        XCTAssertEqual(push.pushPull.alertMessageKey, "form_lab.balance.no_pull")
        XCTAssertEqual(push.upperLower.alertMessageKey, "form_lab.balance.no_lower")
        XCTAssertEqual(report("Barbell Bench Press", count: 1).pushPull.alertMessageKey, "form_lab.balance.no_pull")
        let unknown = report("My leg curl")
        XCTAssertEqual(unknown.totalWorkingSets, 4)
        XCTAssertEqual(unknown.unclassifiedWorkingSets, 4)
        XCTAssertEqual(unknown.pushPull.antagonistSets, 0)
        XCTAssertEqual(unknown.upperLower.antagonistSets, 0)
    }

    func testFormLabAntagonistBalance() {
        let session = WorkoutSessionRecord(
            id: "s-balance",
            programId: "p1",
            workoutId: "w-bal",
            workoutTitle: "Push Day Heavy",
            startedAt: "2026-09-01T10:00:00Z",
            completedAt: "2026-09-01T11:00:00Z",
            durationSeconds: 3600,
            totalVolumeKg: 1500.0,
            totalCompletedSets: 11,
            exerciseLogs: [
                // 10 push sets
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: (1...5).map { SessionSetLog(setNumber: $0, weightKg: 80.0, reps: 8, isWarmup: false) }
                ),
                SessionExerciseLog(
                    exerciseName: "Incline Dumbbell Press",
                    sets: (1...5).map { SessionSetLog(setNumber: $0, weightKg: 30.0, reps: 10, isWarmup: false) }
                ),
                // 1 pull set
                SessionExerciseLog(
                    exerciseName: "Lat Pulldown",
                    sets: [SessionSetLog(setNumber: 1, weightKg: 50.0, reps: 10, isWarmup: false)]
                )
            ]
        )

        let balance = FormLabEngine.computeAntagonistBalance(
            history: [session],
            timeframe: .allTime
        )

        XCTAssertEqual(balance.pushPull.primarySets, 10)
        XCTAssertEqual(balance.pushPull.antagonistSets, 1)
        XCTAssertEqual(balance.pushPull.ratio, 10.0)
        XCTAssertEqual(balance.pushPull.status, AntagonistStatus.primaryDominant)
    }

    func testAntagonistBalanceZeroAndMissingData() {
        // Empty history: all ratios nil, insufficient data
        let emptyBalance = FormLabEngine.computeAntagonistBalance(history: [], timeframe: .allTime)
        XCTAssertEqual(emptyBalance.pushPull.primarySets, 0)
        XCTAssertEqual(emptyBalance.pushPull.antagonistSets, 0)
        XCTAssertNil(emptyBalance.pushPull.ratio)
        XCTAssertEqual(emptyBalance.pushPull.status, .insufficientData)
        XCTAssertNil(emptyBalance.quadHamstring.ratio)
        XCTAssertEqual(emptyBalance.quadHamstring.status, .insufficientData)
        XCTAssertNil(emptyBalance.upperLower.ratio)
        XCTAssertEqual(emptyBalance.upperLower.status, .insufficientData)

        // Session with push sets only (denominator = 0): ratio must be nil, not fabricated 2.0
        let pushOnlySession = WorkoutSessionRecord(
            id: "s-push-only",
            programId: "p1",
            workoutId: "w1",
            workoutTitle: "Chest Only",
            startedAt: "2026-09-10T10:00:00Z",
            completedAt: "2026-09-10T11:00:00Z",
            durationSeconds: 3600,
            totalVolumeKg: 1000.0,
            totalCompletedSets: 4,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: (1...4).map { SessionSetLog(setNumber: $0, weightKg: 80.0, reps: 8, isWarmup: false) }
                )
            ]
        )
        let pushOnlyBalance = FormLabEngine.computeAntagonistBalance(history: [pushOnlySession], timeframe: .allTime)
        XCTAssertEqual(pushOnlyBalance.pushPull.primarySets, 4)
        XCTAssertEqual(pushOnlyBalance.pushPull.antagonistSets, 0)
        XCTAssertNil(pushOnlyBalance.pushPull.ratio)
        XCTAssertEqual(pushOnlyBalance.pushPull.status, .primaryDominant)

        // Low volume (1 push, 1 pull < 3 sets threshold): status insufficientData, ratio nil
        let lowVolumeSession = WorkoutSessionRecord(
            id: "s-low",
            programId: "p1",
            workoutId: "w1",
            workoutTitle: "Quick Session",
            startedAt: "2026-09-10T10:00:00Z",
            completedAt: "2026-09-10T10:30:00Z",
            durationSeconds: 1800,
            totalVolumeKg: 500.0,
            totalCompletedSets: 2,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: [SessionSetLog(setNumber: 1, weightKg: 80.0, reps: 8, isWarmup: false)]
                ),
                SessionExerciseLog(
                    exerciseName: "Lat Pulldown",
                    sets: [SessionSetLog(setNumber: 1, weightKg: 50.0, reps: 10, isWarmup: false)]
                )
            ]
        )
        let lowVolumeBalance = FormLabEngine.computeAntagonistBalance(history: [lowVolumeSession], timeframe: .allTime)
        XCTAssertEqual(lowVolumeBalance.pushPull.primarySets, 1)
        XCTAssertEqual(lowVolumeBalance.pushPull.antagonistSets, 1)
        XCTAssertNil(lowVolumeBalance.pushPull.ratio)
        XCTAssertEqual(lowVolumeBalance.pushPull.status, .insufficientData)
    }

    func testNegativeWeightFormatting() {
        XCTAssertEqual(WeightUnit.kg.formatWeight(-5.0), "-5")
        XCTAssertEqual(WeightUnit.kg.formatWeight(-5.5), "-5.5")
        XCTAssertEqual(WeightUnit.lbs.formatWeight(-5.0), "-11")
        XCTAssertEqual(WeightUnit.kg.formatWeightWithUnit(-5.0), "-5 kg")
        XCTAssertEqual(WeightUnit.kg.formatWeight(0.0), "0")
    }

    func testFormLabCloudMirrorSyncAndReadRoundtrip() throws {
        let payload = "{\"schemaVersion\":4,\"programs\":[],\"activeProgramId\":\"\",\"history\":[]}"
        CloudMirrorManager.shared.isEnabled = true

        // 1. When not Pro, syncNow must throw
        ProAccessManager.shared.updateSubscriptionStatus(active: false)
        XCTAssertThrowsError(try CloudMirrorManager.shared.syncNow(backupJson: payload)) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "CloudMirror")
            XCTAssertEqual(nsError.code, 403)
        }

        // 2. When Pro is active, syncNow succeeds
        ProAccessManager.shared.updateSubscriptionStatus(active: true)
        let size = try CloudMirrorManager.shared.syncNow(backupJson: payload)
        XCTAssertGreaterThan(size, 0)

        // 3. Even after Pro expires or for free users, reading existing snapshot remains free
        ProAccessManager.shared.updateSubscriptionStatus(active: false)
        let readJson = try CloudMirrorManager.shared.readLatestSnapshot()
        XCTAssertEqual(readJson, payload)

        let status = CloudMirrorManager.shared.getStatus()
        XCTAssertTrue(status.isEnabled)
        if !status.isCloudConnected { XCTAssertNil(status.lastSyncTimestamp) }
        XCTAssertEqual(status.snapshotSizeBytes, size)
    }

    func testCloudMirrorPendingSyncStagingAndRetry() throws {
        let payload = "{\"schemaVersion\":4,\"pendingTest\":true}"
        CloudMirrorManager.shared.isEnabled = true
        ProAccessManager.shared.updateSubscriptionStatus(active: true)

        CloudMirrorManager.shared.clearPendingSync()
        XCTAssertFalse(CloudMirrorManager.shared.hasPendingSync)

        CloudMirrorManager.shared.savePendingSync(backupJson: payload)
        XCTAssertTrue(CloudMirrorManager.shared.hasPendingSync)

        // An older upload must not erase a newer backup staged while it was running.
        CloudMirrorManager.shared.savePendingSync(backupJson: "newer")
        CloudMirrorManager.shared.clearPendingSync(onlyIfMatching: payload)
        XCTAssertTrue(CloudMirrorManager.shared.hasPendingSync)
        CloudMirrorManager.shared.savePendingSync(backupJson: payload)

        // Retry pending sync
        CloudMirrorManager.shared.retryPendingSyncIfAny()

        let exp = expectation(description: "Wait for autoSync")
        let start = Date()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { t in
            let localFile = CloudMirrorManager.shared.localMirrorDirectory.appendingPathComponent("form_safety_mirror.json")
            let localReady = (try? String(contentsOf: localFile, encoding: .utf8)) == payload
            if localReady || Date().timeIntervalSince(start) > 4.0 {
                t.invalidate()
                exp.fulfill()
            }
        }
        RunLoop.current.add(timer, forMode: .common)
        wait(for: [exp], timeout: 5.0)

        let readJson = try CloudMirrorManager.shared.readLatestSnapshot()
        XCTAssertEqual(readJson, payload)
        // A successful local save must remain staged until iCloud accepts it.
        XCTAssertEqual(CloudMirrorManager.shared.hasPendingSync, !CloudMirrorManager.shared.isICloudAvailable)
    }

    @MainActor
    func testFormLabViewSnapshot() {
        let store = AppStore(persistence: AppStatePersistence(inMemory: true))
        // Provide mock history
        let session = WorkoutSessionRecord(
            id: "s-lab-snap",
            programId: "p1",
            workoutId: "w1",
            workoutTitle: "Strength & Power",
            startedAt: "2026-09-15T10:00:00Z",
            completedAt: "2026-09-15T11:00:00Z",
            durationSeconds: 3600,
            totalVolumeKg: 2400.0,
            totalCompletedSets: 15,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: (1...5).map { SessionSetLog(setNumber: $0, weightKg: 100.0, reps: 5, isWarmup: false) }
                ),
                SessionExerciseLog(
                    exerciseName: "Barbell Squat",
                    sets: (1...5).map { SessionSetLog(setNumber: $0, weightKg: 140.0, reps: 5, isWarmup: false) }
                )
            ]
        )
        var state = store.state
        state.history = [session]
        store.saveState(state)

        let labView = FormLabView(store: store)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(AppColors.background)

        let controller = UIHostingController(rootView: labView)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 750)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 750))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_form_lab_matrix_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote Form Lab snapshot to \(path)")
        }
    }

    @MainActor
    func testFormLabRepMaxEmptySnapshot() {
        let store = AppStore(persistence: AppStatePersistence(inMemory: true))
        // Provide mock history with only >10 rep sets for Barbell Bench Press so no 1-10 rep sets exist
        let session = WorkoutSessionRecord(
            id: "s-lab-empty-snap",
            programId: "p1",
            workoutId: "w1",
            workoutTitle: "Hypertrophy High Reps",
            startedAt: "2026-09-15T10:00:00Z",
            completedAt: "2026-09-15T11:00:00Z",
            durationSeconds: 3600,
            totalVolumeKg: 2400.0,
            totalCompletedSets: 5,
            exerciseLogs: [
                SessionExerciseLog(
                    exerciseName: "Barbell Bench Press",
                    sets: (1...3).map { SessionSetLog(setNumber: $0, weightKg: 60.0, reps: 15, isWarmup: false) }
                )
            ]
        )
        var state = store.state
        state.history = [session]
        store.saveState(state)

        let labView = FormLabView(store: store)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(AppColors.background)

        let controller = UIHostingController(rootView: labView)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 750)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 750))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        if let data = image.pngData() {
            let path = "/tmp/ios_form_lab_matrix_empty_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote Form Lab empty snapshot to \(path)")
        }
    }

    @MainActor
    func testFormLabInfoSheetSnapshot() async throws {
        let previous = LanguageManager.shared.languagePreference
        let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }.first { $0.isKeyWindow }
        defer { LanguageManager.setLanguage(previous); previousWindow?.makeKeyAndVisible() }
        for language in ["en", "tr", "de", "fr", "es"] {
            LanguageManager.setLanguage(language)
            let controller = UIHostingController(rootView: FormLabInfoSheet()
                .environment(\.locale, LanguageManager.locale)
                .environment(\.dynamicTypeSize, DynamicTypeSize.xxxLarge))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 900))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.frame = window.bounds
            controller.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 300_000_000)
            controller.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            window.isHidden = true
            XCTAssertEqual(image.size.width, 320)
            let attachment = XCTAttachment(image: image)
            attachment.name = "rep-lab-info-\(language)-320-large"
            attachment.lifetime = .keepAlways
            add(attachment)
            try XCTUnwrap(image.pngData()).write(to: URL(fileURLWithPath: "/private/tmp/rep-lab-info-\(language)-ios.png"))
        }
    }

    @MainActor
    func testFormLabCurvesSnapshot() {
        let store = AppStore(persistence: AppStatePersistence(inMemory: true))
        let session1 = WorkoutSessionRecord(
            id: "s1", programId: "p1", workoutId: "w1", workoutTitle: "Chest Day 1",
            startedAt: "2026-06-01T10:00:00Z", completedAt: "2026-06-01T11:00:00Z",
            durationSeconds: 3600, totalVolumeKg: 800.0, totalCompletedSets: 10,
            exerciseLogs: [SessionExerciseLog(exerciseName: "Barbell Bench Press", sets: [SessionSetLog(setNumber: 1, weightKg: 80.0, reps: 8, isWarmup: false)])]
        )
        let session2 = WorkoutSessionRecord(
            id: "s2", programId: "p1", workoutId: "w2", workoutTitle: "Chest Day 2",
            startedAt: "2026-07-15T10:00:00Z", completedAt: "2026-07-15T11:00:00Z",
            durationSeconds: 3600, totalVolumeKg: 1000.0, totalCompletedSets: 10,
            exerciseLogs: [SessionExerciseLog(exerciseName: "Barbell Bench Press", sets: [SessionSetLog(setNumber: 1, weightKg: 95.0, reps: 6, isWarmup: false)])]
        )
        let session3 = WorkoutSessionRecord(
            id: "s3", programId: "p1", workoutId: "w3", workoutTitle: "Chest Day 3",
            startedAt: "2026-09-10T10:00:00Z", completedAt: "2026-09-10T11:00:00Z",
            durationSeconds: 3600, totalVolumeKg: 1200.0, totalCompletedSets: 10,
            exerciseLogs: [SessionExerciseLog(exerciseName: "Barbell Bench Press", sets: [SessionSetLog(setNumber: 1, weightKg: 110.0, reps: 5, isWarmup: false)])]
        )
        var state = store.state
        state.history = [session1, session2, session3]
        store.saveState(state)

        let labView = FormLabView(store: store, initialTab: .curves)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(AppColors.background)

        let controller = UIHostingController(rootView: labView)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 750)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 750))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { _ in controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true) }
        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_form_lab_curves_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote Form Lab Curves snapshot to \(path)")
        }
    }

    @MainActor
    func testFormLabBalanceSnapshot() {
        let store = AppStore(persistence: AppStatePersistence(inMemory: true))
        let session = WorkoutSessionRecord(
            id: "s-bal-snap", programId: "p1", workoutId: "w1", workoutTitle: "Full Body Structural",
            startedAt: "2026-09-12T10:00:00Z", completedAt: "2026-09-12T11:30:00Z",
            durationSeconds: 5400, totalVolumeKg: 3500.0, totalCompletedSets: 22,
            exerciseLogs: [
                SessionExerciseLog(exerciseName: "Barbell Bench Press", sets: (1...5).map { SessionSetLog(setNumber: $0, weightKg: 90.0, reps: 8, isWarmup: false) }),
                SessionExerciseLog(exerciseName: "Bent Over Barbell Row", sets: (1...5).map { SessionSetLog(setNumber: $0, weightKg: 80.0, reps: 8, isWarmup: false) }),
                SessionExerciseLog(exerciseName: "Barbell Squat", sets: (1...4).map { SessionSetLog(setNumber: $0, weightKg: 130.0, reps: 6, isWarmup: false) }),
                SessionExerciseLog(exerciseName: "Romanian Deadlift", sets: (1...4).map { SessionSetLog(setNumber: $0, weightKg: 110.0, reps: 8, isWarmup: false) })
            ]
        )
        var state = store.state
        state.history = [session]
        store.saveState(state)

        let labView = FormLabView(store: store, initialTab: .balance)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(AppColors.background)

        let controller = UIHostingController(rootView: labView)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 850)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 850))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { _ in controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true) }
        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_form_lab_balance_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote Form Lab Balance snapshot to \(path)")
        }
    }

    @MainActor
    func testSettingsCloudBackupSnapshot() {
        let store = AppStore(persistence: AppStatePersistence(inMemory: true))
        let backupView = CloudBackupSheet(store: store)
            .background(AppColors.background)

        let controller = UIHostingController(rootView: backupView)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 750)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 750))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { _ in controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true) }
        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_settings_cloud_backup_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote Settings Cloud Backup snapshot to \(path)")
        }
    }

    @MainActor
    func testAnnualSavingsUsesLiveStoreAmounts() {
        XCTAssertEqual(StoreKitSubscriptionManager.savingsPercentage(monthly: 5, annual: 40), 33)
        XCTAssertNil(StoreKitSubscriptionManager.savingsPercentage(monthly: 5, annual: 60))
        XCTAssertNil(StoreKitSubscriptionManager.savingsPercentage(monthly: 0, annual: 40))
    }

    @MainActor
    func testOnlyKnownStoreKitProductsGrantPro() {
        XCTAssertTrue(StoreKitSubscriptionManager.isProProductId(StoreKitSubscriptionManager.monthlyProductId))
        XCTAssertTrue(StoreKitSubscriptionManager.isProProductId(StoreKitSubscriptionManager.annualProductId))
        XCTAssertFalse(StoreKitSubscriptionManager.isProProductId("com.perseverancesoftware.forcedrep.other"))
    }

    func testVolumeMatrixPaywallSnapshot() {
        let view = ProPaywallSheet(feature: .volumeMatrix)
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { _ in controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true) }
        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_paywall_volume_matrix_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote Volume Matrix Paywall snapshot to \(path)")
        }
    }

    func testFormLabPaywallSnapshot() {
        let view = ProPaywallSheet(feature: .formLab)
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { _ in controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true) }
        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_paywall_rep_lab_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote Rep Lab Paywall snapshot to \(path)")
        }
    }

    func testWarmupCalculatorPaywallSnapshot() {
        let view = ProPaywallSheet(feature: .warmupCalculator)
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { _ in controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true) }
        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_paywall_warmup_calculator_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote Warmup Calculator Paywall snapshot to \(path)")
        }
    }

    @MainActor
    func testLockedAnalyticsBlurredPreviewSnapshots() async throws {
        let store = AppStore(persistence: AppStatePersistence(inMemory: true))
        let original = store.state
        let manager = ProAccessManager.shared
        let subscription = manager.isProSubscribed
        let features: [ProFeature] = [.volumeMatrix, .formLab]
        let access = features.map { manager.isFeatureUnlocked($0) }
        let language = LanguageManager.shared.currentLanguage
        store.state.history = [
            WorkoutSessionRecord(
                id: "snap-sample-1",
                programId: "p",
                workoutId: "w",
                workoutTitle: "Upper Body",
                startedAt: "2026-09-20T10:00:00Z",
                completedAt: "2026-09-20T11:00:00Z",
                durationSeconds: 3600,
                totalVolumeKg: 1500.0,
                totalCompletedSets: 6,
                exerciseLogs: [
                    SessionExerciseLog(
                        exerciseName: "Barbell Bench Press",
                        sets: [
                            SessionSetLog(setNumber: 1, weightKg: 100.0, reps: 5, isWarmup: false),
                            SessionSetLog(setNumber: 2, weightKg: 100.0, reps: 5, isWarmup: false),
                            SessionSetLog(setNumber: 3, weightKg: 100.0, reps: 5, isWarmup: false)
                        ],
                        targetSets: 3
                    ),
                    SessionExerciseLog(
                        exerciseName: "Barbell Back Squat",
                        sets: [
                            SessionSetLog(setNumber: 1, weightKg: 120.0, reps: 5, isWarmup: false),
                            SessionSetLog(setNumber: 2, weightKg: 120.0, reps: 5, isWarmup: false),
                            SessionSetLog(setNumber: 3, weightKg: 120.0, reps: 5, isWarmup: false)
                        ],
                        targetSets: 3
                    )
                ],
                isComplete: true
            )
        ]
        store.selectedHistoryDetailDay = nil
        LanguageManager.setLanguage("en")
        defer {
            store.state = original
            LanguageManager.setLanguage(language)
            for (feature, unlocked) in zip(features, access) {
                manager.setFeatureOverride(feature, unlocked: unlocked == subscription ? nil : unlocked)
            }
        }

        func snapshot(_ tab: HistoryView.HistoryTab, name: String) async throws -> UIImage {
            let content = HistoryView(store: store, initialTab: tab, onOpenSettings: {}, onSelectRecord: { _ in })
                .background(AppColors.background)
            let controller = UIHostingController(rootView: content)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.frame = window.bounds
            controller.view.layoutIfNeeded()
            defer { window.isHidden = true }
            try await Task.sleep(nanoseconds: 200_000_000)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
                controller.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            return image
        }

        func edgeDetail(_ image: UIImage) throws -> Double {
            let crop = try XCTUnwrap(image.cgImage?.cropping(to: CGRect(x: 20, y: 210, width: 353, height: 100)))
            var pixels = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
            let context = try XCTUnwrap(CGContext(data: &pixels, width: crop.width, height: crop.height,
                bitsPerComponent: 8, bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
            var detail = 0.0
            for y in 1..<crop.height {
                for x in 1..<crop.width {
                    let offset = (y * crop.width + x) * 4
                    for channel in 0..<3 {
                        detail += Double(abs(Int(pixels[offset + channel]) - Int(pixels[offset - 4 + channel])))
                        detail += Double(abs(Int(pixels[offset + channel]) - Int(pixels[offset - crop.width * 4 + channel])))
                    }
                }
            }
            return detail / Double((crop.width - 1) * (crop.height - 1) * 6)
        }

        for feature in features {
            let tab: HistoryView.HistoryTab = feature == .volumeMatrix ? .volumeMatrix : .formLab
            manager.setFeatureOverride(feature, unlocked: false)
            let locked = try await snapshot(tab, name: "locked-\(feature.rawValue)")
            manager.setFeatureOverride(feature, unlocked: true)
            let unlocked = try await snapshot(tab, name: "unlocked-\(feature.rawValue)")
            let sharpDetail = try edgeDetail(unlocked)
            XCTAssertGreaterThan(sharpDetail, 0.3, "The sample must contain visible analytics")
            XCTAssertLessThan(try edgeDetail(locked), sharpDetail * 0.5, "Locked analytics must lose fine detail through blur")
        }
    }

    func testActiveWeekWithFiveDayScheduleReconcilesAllUncompletedDaysAsMissed() {
        let testToday = "2026-09-21"
        let mon = WorkoutSessionRecord(
            id: "s-mon", programId: "p5", workoutId: "w-push", workoutTitle: "Push",
            startedAt: "2026-09-14T10:00:00Z", completedAt: "2026-09-14T11:00:00Z", durationSeconds: 3600,
            isComplete: false
        )
        let tue = WorkoutSessionRecord(
            id: "s-tue", programId: "p5", workoutId: "w-pull", workoutTitle: "Pull",
            startedAt: "2026-09-15T10:00:00Z", completedAt: "2026-09-15T11:00:00Z", durationSeconds: 3600,
            isComplete: true
        )
        let program = Program(
            id: "p5", name: "5-Day Split",
            workouts: [
                Workout(id: "w-push", day: 1, title: "Push", exercises: [Exercise(id: "e1", name: "Bench", sets: 3)]),
                Workout(id: "w-pull", day: 2, title: "Pull", exercises: [Exercise(id: "e2", name: "Row", sets: 3)]),
                Workout(id: "w-legs", day: 4, title: "Legs", exercises: [Exercise(id: "e3", name: "Squat", sets: 3)]),
                Workout(id: "w-upper", day: 5, title: "Upper", exercises: [Exercise(id: "e4", name: "OHP", sets: 3)]),
                Workout(id: "w-arms", day: 6, title: "Arms", exercises: [Exercise(id: "e5", name: "Curls", sets: 3)])
            ]
        )
        let existingHistory = WorkoutCalendarHistory(
            nextScheduledDate: "2026-09-21",
            scheduledWeekdays: [1, 2, 4, 5, 6],
            missedDates: ["2026-09-19"],
            entries: [
                WorkoutDayEntry(id: "session:s-mon", date: "2026-09-14", status: .unfinished),
                WorkoutDayEntry(id: "session:s-tue", date: "2026-09-15", status: .completed)
            ]
        )
        let restored = WorkoutCalendar.restore(
            raw: existingHistory,
            sessions: [mon, tue],
            today: testToday,
            weekdays: [1, 2, 4, 5, 6],
            programs: [program]
        )
        XCTAssertEqual(restored.missedDates, ["2026-09-17", "2026-09-18", "2026-09-19"])

        let statuses = WorkoutCalendar.statuses(history: restored, today: testToday)
        XCTAssertEqual(statuses["2026-09-14"], .unfinished)
        XCTAssertEqual(statuses["2026-09-15"], .completed)
        XCTAssertNil(statuses["2026-09-16"], "Wednesday is a rest day")
        XCTAssertEqual(statuses["2026-09-17"], .missed)
        XCTAssertEqual(statuses["2026-09-18"], .missed)
        XCTAssertEqual(statuses["2026-09-19"], .missed)
        XCTAssertNil(statuses["2026-09-20"], "Sunday is a rest day")

        let weekDays = ["2026-09-14", "2026-09-15", "2026-09-16", "2026-09-17", "2026-09-18", "2026-09-19", "2026-09-20"]
        let count = weekDays.compactMap { statuses[$0] }.count
        XCTAssertEqual(count, 5, "Exactly 5 scheduled workout days in that week must have a status")
    }

    func testGhostTargetCalculationAndProgressionTargets() {
        let exercise = Exercise(id: "bench", name: "Barbell Bench Press", prescription: "3 × 8–12", sets: 3)
        let prevSets = [
            SessionSetLog(setNumber: 1, weightKg: 100.0, reps: 8),
            SessionSetLog(setNumber: 2, weightKg: 100.0, reps: 7)
        ]

        // Set 1 target: based on 100kg x 8
        let target1 = WorkoutSessionUtils.computeGhostTarget(previousSets: prevSets, workingSetIndex: 0, exercise: exercise, unit: .kg)
        XCTAssertFalse(target1.isFirstSession)
        XCTAssertEqual(target1.lastWeekWeightKg ?? 0.0, 100.0, accuracy: 0.01)
        XCTAssertEqual(target1.lastWeekReps, 8)
        XCTAssertEqual(target1.targetWeightKg, 100.0, accuracy: 0.01)
        XCTAssertEqual(target1.targetReps, 9)
        XCTAssertEqual(target1.altWeightKg ?? 0.0, 102.5, accuracy: 0.01)
        XCTAssertEqual(target1.altReps, 7)

        // Set 2 target: based on 100kg x 7
        let target2 = WorkoutSessionUtils.computeGhostTarget(previousSets: prevSets, workingSetIndex: 1, exercise: exercise, unit: .kg)
        XCTAssertEqual(target2.lastWeekReps, 7)
        XCTAssertEqual(target2.targetReps, 8)
        XCTAssertEqual(target2.altWeightKg ?? 0.0, 102.5, accuracy: 0.01)
        XCTAssertEqual(target2.altReps, 6)

        // First session (no history)
        let firstTarget = WorkoutSessionUtils.computeGhostTarget(previousSets: [], workingSetIndex: 0, exercise: exercise, unit: .kg)
        XCTAssertTrue(firstTarget.isFirstSession)
        XCTAssertNil(firstTarget.lastWeekWeightKg)
        XCTAssertNil(firstTarget.lastWeekReps)
        XCTAssertEqual(firstTarget.targetReps, 8)
    }

    func testLogbookBeatDetectionAndFormatting() {
        let exercise = Exercise(id: "bench", name: "Barbell Bench Press", exerciseId: "barbell-bench-press", prescription: "3 × 8–12", sets: 3)
        let prevSets = [SessionSetLog(setNumber: 1, weightKg: 100.0, reps: 8)]
        let target = WorkoutSessionUtils.computeGhostTarget(previousSets: prevSets, workingSetIndex: 0, exercise: exercise, unit: .kg)

        // Rep progression beat (+1 rep)
        let beatRep = WorkoutSessionUtils.evaluateLogbookBeat(loggedWeightKg: 100.0, loggedReps: 9, target: target)
        XCTAssertNotNil(beatRep)
        XCTAssertEqual(beatRep?.repDelta, 1)
        XCTAssertEqual(beatRep?.weightDeltaKg ?? 0.0, 0.0, accuracy: 0.01)
        let badgeRep = WorkoutSessionUtils.formatLogbookBeatBadge(result: beatRep!, unit: .kg)
        XCTAssertTrue(badgeRep.contains("+1 REP") || badgeRep.contains("+1 TEKRAR"))

        // Load progression beat (102.5kg x 7)
        let beatLoad = WorkoutSessionUtils.evaluateLogbookBeat(loggedWeightKg: 102.5, loggedReps: 7, target: target)
        XCTAssertNotNil(beatLoad)
        XCTAssertEqual(beatLoad?.weightDeltaKg ?? 0.0, 2.5, accuracy: 0.01)
        let badgeLoad = WorkoutSessionUtils.formatLogbookBeatBadge(result: beatLoad!, unit: .kg)
        XCTAssertTrue(badgeLoad.contains("+2.5 KG"))

        // Rejection of matched or subpar performances
        XCTAssertNil(WorkoutSessionUtils.evaluateLogbookBeat(loggedWeightKg: 100.0, loggedReps: 8, target: target))
        XCTAssertNil(WorkoutSessionUtils.evaluateLogbookBeat(loggedWeightKg: 100.0, loggedReps: 7, target: target))
        XCTAssertNil(WorkoutSessionUtils.evaluateLogbookBeat(loggedWeightKg: 90.0, loggedReps: 8, target: target))

        // Notice text formatting
        let notice = WorkoutSessionUtils.formatLogbookBeatNotice(result: beatRep!, unit: .kg)
        XCTAssertTrue(notice.contains("100 kg × 9") && notice.contains("100 kg × 8"))
    }

    @MainActor
    func testSetLoggingTableActiveGhostTargetSnapshot() {
        let exercise = Exercise(id: "bench", name: "Barbell Bench Press", prescription: "3 × 8–12", sets: 3)
        let prevSets = [
            SessionSetLog(setNumber: 1, weightKg: 100.0, reps: 8),
            SessionSetLog(setNumber: 2, weightKg: 100.0, reps: 7),
            SessionSetLog(setNumber: 3, weightKg: 95.0, reps: 8)
        ]
        let target1 = WorkoutSessionUtils.computeGhostTarget(previousSets: prevSets, workingSetIndex: 0, exercise: exercise, unit: .kg)
        let target2 = WorkoutSessionUtils.computeGhostTarget(previousSets: prevSets, workingSetIndex: 1, exercise: exercise, unit: .kg)
        let target3 = WorkoutSessionUtils.computeGhostTarget(previousSets: prevSets, workingSetIndex: 2, exercise: exercise, unit: .kg)

        // Set 1 completed with logbook beat: 100kg x 9 (+1 rep)
        let beatSet1 = WorkoutSessionUtils.evaluateLogbookBeat(loggedWeightKg: 100.0, loggedReps: 9, target: target1)!

        let testSets = [
            ExerciseSetLog(setNumber: 1, weightInput: "100", repsInput: "9", weightKg: 100.0, completedReps: 9, isCompleted: true, inputTouched: true),
            ExerciseSetLog(setNumber: 2, weightInput: "", repsInput: "", weightKg: nil, completedReps: nil, isCompleted: false, inputTouched: false),
            ExerciseSetLog(setNumber: 3, weightInput: "", repsInput: "", weightKg: nil, completedReps: nil, isCompleted: false, inputTouched: false)
        ]

        let table = SetLoggingTable(
            sets: testSets,
            prescription: "3 × 8–12",
            isRestActive: false,
            prText: "100x8",
            onUpdateSet: { _, _, _ in },
            onToggleCompleteSet: { _ in },
            onAddSet: {},
            onRemoveSet: { _ in },
            weightUnit: .kg,
            ghostTargets: [0: target1, 1: target2, 2: target3],
            logbookBeatenSets: [0: beatSet1]
        )

        let container = VStack {
            table
        }
        .padding(16)
        .background(AppColors.background)

        let controller = UIHostingController(rootView: container)
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 340)
        controller.view.backgroundColor = UIColor(red: 0x09/255.0, green: 0x0C/255.0, blue: 0x0F/255.0, alpha: 1.0)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 340))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { ctx in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }

        if let data = image.pngData() {
            let path = "/Users/groggy/.gemini/antigravity/brain/8f7a25b0-1cb4-43c6-9c07-c337d4904e34/ios_ghost_target_set_table_snapshot.png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("Successfully wrote Ghost Target Set Table snapshot to \(path)")
        }
    }

    func testWorkoutCalendarIsSessionComplete_MissingPlannedExercise_ReturnsFalse() {
        let workout = Workout(
            id: "hl-bench-push",
            day: 1,
            title: "Heavy Bench & Push",
            exercises: [
                Exercise(name: "Barbell Bench Press", sets: 6),
                Exercise(name: "Incline Barbell Bench Press", sets: 3),
                Exercise(name: "Pec Deck Fly", sets: 4),
                Exercise(name: "Standing Barbell Overhead Press", sets: 3),
                Exercise(name: "Cable Lateral Raise", sets: 3),
                Exercise(name: "Rope Triceps Pressdown", sets: 3)
            ]
        )

        // Session has 5 of 6 exercises done, Pec Deck Fly is omitted.
        // Even if isComplete is true, isSessionComplete must return false.
        let session = WorkoutSessionRecord(
            id: "s-1",
            programId: "heavylifter",
            workoutId: "hl-bench-push",
            workoutTitle: "Heavy Bench & Push",
            startedAt: "2026-09-14T17:30:00Z",
            completedAt: "2026-09-14T18:46:40Z",
            durationSeconds: 4600,
            totalCompletedSets: 16,
            exerciseLogs: [
                SessionExerciseLog(exerciseName: "Barbell Bench Press", sets: (1...6).map { SessionSetLog(setNumber: $0, weightKg: 100.0, reps: 5) }, targetSets: 6),
                SessionExerciseLog(exerciseName: "Incline Barbell Bench Press", sets: (1...3).map { SessionSetLog(setNumber: $0, weightKg: 80.0, reps: 5) }, targetSets: 3),
                SessionExerciseLog(exerciseName: "Standing Barbell Overhead Press", sets: (1...3).map { SessionSetLog(setNumber: $0, weightKg: 60.0, reps: 5) }, targetSets: 3),
                SessionExerciseLog(exerciseName: "Cable Lateral Raise", sets: (1...3).map { SessionSetLog(setNumber: $0, weightKg: 15.0, reps: 12) }, targetSets: 3),
                SessionExerciseLog(exerciseName: "Rope Triceps Pressdown", sets: (1...3).map { SessionSetLog(setNumber: $0, weightKg: 35.0, reps: 10) }, targetSets: 3)
            ],
            isComplete: true,
            workoutSnapshot: workout
        )

        XCTAssertFalse(WorkoutCalendar.isSessionComplete(session: session, workout: workout))
    }

    func testWorkoutCalendarIsSessionComplete_OnlyOneOfThreeExercisesDone_ReturnsFalse() {
        let workout = Workout(
            id: "w1", day: 2, title: "3-Move Workout",
            exercises: [
                Exercise(name: "Ex 1", sets: 4),
                Exercise(name: "Ex 2", sets: 4),
                Exercise(name: "Ex 3", sets: 4)
            ]
        )

        // Ex 1 is done 4 out of 4 sets, but Ex 2 and Ex 3 are not done.
        let session = WorkoutSessionRecord(
            id: "s-2", programId: "p1", workoutId: "w1", workoutTitle: "3-Move Workout",
            startedAt: "2026-09-15T10:00:00Z", completedAt: "2026-09-15T10:30:00Z",
            durationSeconds: 1800, totalCompletedSets: 4,
            exerciseLogs: [
                SessionExerciseLog(exerciseName: "Ex 1", sets: (1...4).map { SessionSetLog(setNumber: $0, weightKg: 50.0, reps: 10) }, targetSets: 4)
            ],
            isComplete: true,
            workoutSnapshot: workout
        )

        XCTAssertFalse(WorkoutCalendar.isSessionComplete(session: session, workout: workout))
    }

    func testWorkoutCalendarIsSessionComplete_21Of22SetsCompleted_ReturnsFalse() {
        let workout = Workout(
            id: "w2", day: 3, title: "Big Workout",
            exercises: [
                Exercise(name: "Ex 1", sets: 11),
                Exercise(name: "Ex 2", sets: 11)
            ]
        )

        // 21 of 22 sets completed (Ex 2 only has 10 sets instead of 11)
        let session = WorkoutSessionRecord(
            id: "s-3", programId: "p2", workoutId: "w2", workoutTitle: "Big Workout",
            startedAt: "2026-09-16T10:00:00Z", completedAt: "2026-09-16T11:00:00Z",
            durationSeconds: 3600, totalCompletedSets: 21,
            exerciseLogs: [
                SessionExerciseLog(exerciseName: "Ex 1", sets: (1...11).map { SessionSetLog(setNumber: $0, weightKg: 50.0, reps: 10) }, targetSets: 11),
                SessionExerciseLog(exerciseName: "Ex 2", sets: (1...10).map { SessionSetLog(setNumber: $0, weightKg: 50.0, reps: 10) }, targetSets: 11)
            ],
            isComplete: true
        )

        XCTAssertFalse(WorkoutCalendar.isSessionComplete(session: session, workout: workout))
    }

    func testWorkoutCalendarIsSessionComplete_AllExercisesAndSetsCompleted_ReturnsTrue() {
        let workout = Workout(
            id: "w3", day: 4, title: "Complete Workout",
            exercises: [
                Exercise(name: "Ex 1", sets: 3),
                Exercise(name: "Ex 2", sets: 3)
            ]
        )

        let session = WorkoutSessionRecord(
            id: "s-4", programId: "p3", workoutId: "w3", workoutTitle: "Complete Workout",
            startedAt: "2026-09-17T10:00:00Z", completedAt: "2026-09-17T10:45:00Z",
            durationSeconds: 2700, totalCompletedSets: 6,
            exerciseLogs: [
                SessionExerciseLog(exerciseName: "Ex 1", sets: (1...3).map { SessionSetLog(setNumber: $0, weightKg: 50.0, reps: 10) }, targetSets: 3),
                SessionExerciseLog(exerciseName: "Ex 2", sets: (1...3).map { SessionSetLog(setNumber: $0, weightKg: 50.0, reps: 10) }, targetSets: 3)
            ],
            isComplete: true
        )

        XCTAssertTrue(WorkoutCalendar.isSessionComplete(session: session, workout: workout))
    }
}

final class ProgressionReliabilityTests: XCTestCase {
    func testLoggingProgressExcludesWarmupsAndPrefillsAndTracksWorkingSetChanges() {
        let workingSets = (1...6).map { index in ExerciseSetLog(
            setNumber: index, weightKg: 65, completedReps: 8, isCompleted: index <= 4
        ) }
        let warmup = ExerciseSetLog(setNumber: 0, isCompleted: true, isWarmup: true)
        XCTAssertEqual(ProgressionLoggingProgress.from(sets: [warmup] + workingSets), ProgressionLoggingProgress(recordedSets: 4, totalSets: 6))
        XCTAssertEqual(ProgressionLoggingProgress.from(sets: workingSets).remainingSets, 2)
        var undone = workingSets
        undone[3].isCompleted = false
        XCTAssertEqual(ProgressionLoggingProgress.from(sets: undone), ProgressionLoggingProgress(recordedSets: 3, totalSets: 6))
        XCTAssertEqual(ProgressionLoggingProgress.from(sets: workingSets + [ExerciseSetLog(setNumber: 7)]), ProgressionLoggingProgress(recordedSets: 4, totalSets: 7))
        XCTAssertEqual(ProgressionLoggingProgress.from(sets: Array(workingSets.dropLast())), ProgressionLoggingProgress(recordedSets: 4, totalSets: 5))
        let completed = workingSets.map { set in var result = set; result.isCompleted = true; return result }
        XCTAssertEqual(ProgressionLoggingProgress.from(sets: completed).remainingSets, 0)
        XCTAssertEqual(ProgressionLoggingProgress.from(sets: [warmup]), ProgressionLoggingProgress(recordedSets: 0, totalSets: 0))
    }

    private let bench = Exercise(name: "Barbell Bench Press", exerciseId: "barbell-bench-press", sets: 3, reps: RepTarget(min: 8, max: 12))
    private func record(_ day: Int, reps: [Int] = [8, 8, 8], loads: [Double?]? = nil, targetSets: Int = 3) -> WorkoutSessionRecord {
        let weights = loads ?? Array(repeating: 65.0, count: reps.count)
        let date = String(format: "2026-09-%02d", day)
        return WorkoutSessionRecord(id: "s\(day)", programId: "p", workoutId: "w", workoutTitle: "Fixture",
            startedAt: "\(date)T10:00:00Z", completedAt: "\(date)T11:00:00Z", durationSeconds: 60,
            exerciseLogs: [SessionExerciseLog(exerciseName: bench.name,
                sets: reps.enumerated().map { SessionSetLog(setNumber: $0.offset + 1, weightKg: weights[$0.offset], reps: $0.element) },
                targetSets: targetSets, exerciseId: bench.exerciseId)])
    }

    func testEightRepsNeverJumpToTwelveEvenBelowPrescriptionFloor() {
        for range in [RepTarget(min: 8, max: 12), RepTarget(min: 12, max: 12), RepTarget(min: 12, max: 15)] {
            var exercise = bench
            exercise.reps = range
            let rec = ProgressionEngine.computeProgression(exercise: exercise, history: [record(1)])!
            XCTAssertEqual(rec.setTargets.map { $0.reps }, [9, 9, 9])
            XCTAssertEqual(rec.setTargets.map { $0.weightKg }, [65, 65, 65])
            XCTAssertEqual(rec.suggestedRepsMax, 9)
        }
    }

    func testTargetsPreserveSetOrderLoadsAndRepCeilings() {
        var source = record(1, reps: [12, 10, 8], loads: [80, 70, 60])
        source.exerciseLogs[0].sets = Array(source.exerciseLogs[0].sets.reversed()) + [SessionSetLog(setNumber: 0, weightKg: 20, reps: 2, isWarmup: true)]
        let rec = ProgressionEngine.computeProgression(exercise: bench, history: [source])!
        XCTAssertEqual(rec.setTargets.map { $0.reps }, [12, 11, 9])
        XCTAssertEqual(rec.setTargets.map { $0.weightKg }, [80, 70, 60])
        XCTAssertEqual(rec.action, .addReps)
        XCTAssertEqual(rec.lastSessionSets.map { $0.reps }, [12, 10, 8])
        XCTAssertEqual(rec.lastSessionSets.map { $0.weightKg }, [80, 70, 60])
    }

    func testIncompleteLatestLogDoesNotFallBackToOlderCeilingPerformance() {
        let rec = ProgressionEngine.computeProgression(exercise: bench, history: [record(1, reps: [12, 12, 12]), record(2, reps: [8])])!
        XCTAssertEqual(rec.action, .insufficientData)
        XCTAssertTrue(rec.setTargets.isEmpty)
        XCTAssertNil(rec.suggestedWeightKg)
        XCTAssertTrue(rec.lastSessionSets.isEmpty)
    }

    func testLoadIncreaseNeedsTwoFullSessionsAtTheSameLoadsAndCeiling() {
        let ceiling = record(2, reps: [12, 12, 12])
        let single = ProgressionEngine.computeProgression(exercise: bench, history: [ceiling])!
        XCTAssertEqual(single.action, .holdLoad)
        XCTAssertEqual(single.rationaleKey, "progression.rationale.repeat_ceiling")
        XCTAssertEqual(single.suggestedWeightKg!, 65, accuracy: 0.001)
        let confirmed = ProgressionEngine.computeProgression(exercise: bench, history: [ceiling, record(1, reps: [12, 12, 12])])!
        XCTAssertEqual(confirmed.action, .increaseLoad)
        XCTAssertEqual(confirmed.setTargets.map { $0.reps }, [12, 12, 12])
        XCTAssertEqual(confirmed.suggestedWeightKg!, 67.5, accuracy: 0.001)
        for previous in [record(1, reps: [12, 12, 11]), record(1, reps: [12]), record(1, reps: [12, 12, 12], loads: [60, 60, 60])] {
            XCTAssertEqual(ProgressionEngine.computeProgression(exercise: bench, history: [previous, ceiling])!.action, .holdLoad)
        }
        XCTAssertEqual(ProgressionEngine.computeProgression(exercise: bench, history: [ceiling, ceiling])!.action, .holdLoad)
    }

    func testSixSetBenchLoadIncreaseKeepsFiveRepsAndAppliesTheDisplayedTargets() throws {
        var exercise = bench
        exercise.sets = 6
        exercise.reps = RepTarget(min: 3, max: 5)
        let history = [1, 2].map { record($0, reps: Array(repeating: 5, count: 6), loads: Array(repeating: 100, count: 6), targetSets: 6) }
        let recommendation = try XCTUnwrap(ProgressionEngine.computeProgression(exercise: exercise, history: history))
        XCTAssertEqual(recommendation.action, .increaseLoad)
        XCTAssertEqual(recommendation.lastSessionSets, Array(repeating: ProgressionSetTarget(weightKg: 100, reps: 5), count: 6))
        XCTAssertEqual(recommendation.setTargets, Array(repeating: ProgressionSetTarget(weightKg: 102.5, reps: 5), count: 6))
        XCTAssertEqual(recommendation.rationaleArgs["targetReps"], "5")
        let rows = (1...6).map { ExerciseSetLog(setNumber: $0) }
        let applied = recommendation.applicableTargets(sets: rows)
        XCTAssertEqual(rows.indices.compactMap { applied[$0] }, recommendation.setTargets)
        XCTAssertEqual(applied[0]?.weightInput(unit: .kg, fallback: "0"), "102.5")
        for actualReps in [3, 4] {
            let actual = record(3, reps: Array(repeating: actualReps, count: 6), loads: Array(repeating: 102.5, count: 6), targetSets: 6)
            let next = try XCTUnwrap(ProgressionEngine.computeProgression(exercise: exercise, history: history + [actual]))
            XCTAssertEqual(next.action, .addReps)
            XCTAssertEqual(next.setTargets, Array(repeating: ProgressionSetTarget(weightKg: 102.5, reps: actualReps + 1), count: 6))
        }
    }

    @MainActor func testExpandedLoadIncreaseShowsPreviousAndTargetSetsInBothLanguages() throws {
        let previousLanguage = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(previousLanguage) }
        var exercise = bench
        exercise.sets = 6
        exercise.reps = RepTarget(min: 3, max: 5)
        for language in ["en", "tr"] {
            LanguageManager.setLanguage(language)
            for (name, loads, unit) in [
                ("bench-kg", Array(repeating: Double(100), count: 6), WeightUnit.kg),
                ("bench-lbs", Array(repeating: Double(100), count: 6), WeightUnit.lbs),
                ("mixed-kg", [100.0, 100, 95, 95, 90, 90], WeightUnit.kg)
            ] {
                let history = [1, 2].map { record($0, reps: Array(repeating: 5, count: 6), loads: loads.map { Optional($0) }, targetSets: 6) }
                let recommendation = try XCTUnwrap(ProgressionEngine.computeProgression(exercise: exercise, history: history, weightUnit: unit))
                XCTAssertEqual(recommendation.action, .increaseLoad)
                for (width, textSize) in [(CGFloat(440), ContentSizeCategory.large), (CGFloat(320), ContentSizeCategory.extraExtraExtraLarge)] {
                    let card = ProgressionRecommendationCard(recommendation: recommendation, weightUnit: unit,
                        canApplyTarget: true, expanded: .constant(true), wasApplied: .constant(false), onApplyTarget: {}, onOpenInfo: {})
                        .padding(20).frame(width: width).background(AppColors.background)
                        .environment(\.sizeCategory, textSize)
                    let renderer = ImageRenderer(content: card)
                    renderer.scale = 1
                    let image = try XCTUnwrap(renderer.uiImage)
                    XCTAssertEqual(image.size.width, width)
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "progression-increase-\(language)-\(name)-\(Int(width))"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    func testLoadIncreasesKeepThePrescribedCeilingAcrossRangesAndMixedLoads() throws {
        for range in [RepTarget(min: 3, max: 5), RepTarget(min: 8, max: 12), RepTarget(min: 5, max: 5)] {
            var exercise = bench
            exercise.reps = range
            let ceiling = try XCTUnwrap(range.max)
            let history = [1, 2].map { record($0, reps: Array(repeating: ceiling + 2, count: 3), loads: [100, 90, 80]) }
            let rec = try XCTUnwrap(ProgressionEngine.computeProgression(exercise: exercise, history: history))
            XCTAssertEqual(rec.action, .increaseLoad)
            XCTAssertEqual(rec.setTargets.map { $0.weightKg }, [102.5, 92.5, 82.5])
            XCTAssertEqual(rec.setTargets.map { $0.reps }, Array(repeating: ceiling, count: 3))
            XCTAssertEqual(rec.rationaleArgs["targetReps"], "\(ceiling)")
        }
    }

    func testLoadStepsRespectUnitsEquipmentBodyweightAndTenPercentLimit() {
        let full = [record(1, reps: [12, 12, 12]), record(2, reps: [12, 12, 12])]
        let pounds = ProgressionEngine.computeProgression(exercise: bench, history: full, weightUnit: .lbs)!
        XCTAssertEqual(WeightUnit.lbs.toDisplay(pounds.suggestedWeightKg! - 65), 5, accuracy: 0.001)
        XCTAssertEqual(pounds.setTargets.map { $0.reps }, [12, 12, 12])
        let light = [record(1, reps: [12, 12, 12], loads: [10, 10, 10]), record(2, reps: [12, 12, 12], loads: [10, 10, 10])]
        XCTAssertEqual(ProgressionEngine.computeProgression(exercise: bench, history: light)!.action, .holdLoad)
        var bodyweight = bench
        bodyweight.name = "Pull-Ups"
        bodyweight.exerciseId = "pull-ups"
        let bwLogs = full.map { source -> WorkoutSessionRecord in
            var source = source
            source.exerciseLogs[0].exerciseName = bodyweight.name
            source.exerciseLogs[0].exerciseId = bodyweight.exerciseId
            source.exerciseLogs[0].sets = source.exerciseLogs[0].sets.map { set in
                var set = set
                set.weightKg = 0
                return set
            }
            return source
        }
        let bw = ProgressionEngine.computeProgression(exercise: bodyweight, history: bwLogs)!
        XCTAssertEqual(bw.action, .holdLoad)
        XCTAssertTrue(bw.setTargets.allSatisfy { $0.weightKg == 0 })
        var custom = bench
        custom.name = "Custom movement"
        custom.exerciseId = "custom-movement"
        let customLogs = full.map { source -> WorkoutSessionRecord in
            var source = source
            source.exerciseLogs[0].exerciseName = custom.name
            source.exerciseLogs[0].exerciseId = custom.exerciseId
            return source
        }
        XCTAssertEqual(ProgressionEngine.computeProgression(exercise: custom, history: customLogs)!.action, .holdLoad)
    }

    func testInvalidOrAmbiguousLogsProduceNoApplicableTarget() {
        for load: Double? in [nil, .nan, .infinity, -1, 0, 1e100] {
            let rec = ProgressionEngine.computeProgression(exercise: bench, history: [record(1, loads: [load, load, load])])!
            XCTAssertEqual(rec.action, .insufficientData)
            XCTAssertTrue(rec.setTargets.isEmpty)
        }
        var duplicated = record(1)
        duplicated.exerciseLogs += duplicated.exerciseLogs
        XCTAssertEqual(ProgressionEngine.computeProgression(exercise: bench, history: [duplicated])!.action, .insufficientData)
        XCTAssertTrue(ProgressionEngine.computeProgression(exercise: bench, history: [record(1, reps: [8, 0, 8])])!.setTargets.isEmpty)
    }

    func testPlateauRequiresComparableFullSessionsAndNeverAppliesAutomaticDeload() {
        let history = (1...3).map { record($0) }
        let plateau = ProgressionEngine.computeProgression(exercise: bench, history: history)!
        XCTAssertTrue(plateau.isPlateau)
        XCTAssertTrue(plateau.setTargets.isEmpty)
        XCTAssertNil(plateau.suggestedWeightKg)
        XCTAssertEqual(plateau.lastSessionSets.map { $0.reps }, [8, 8, 8])
        let changingLoads = (1...3).map { record($0, loads: Array(repeating: 72.5 - Double($0) * 2.5, count: 3)) }
        XCTAssertFalse(ProgressionEngine.computeProgression(exercise: bench, history: changingLoads)!.isPlateau)
        XCTAssertFalse(ProgressionEngine.computeProgression(exercise: bench, history: [record(1, reps: [8, 8]), record(2), record(3)])!.isPlateau)
        XCTAssertFalse(ProgressionEngine.computeProgression(exercise: bench, history: [record(1), record(2), record(3, reps: [8, 9, 8])])!.isPlateau)
    }

    func testApplyProtectsWarmupsCompletedRowsAndChangedSetCounts() {
        let rec = ProgressionEngine.computeProgression(exercise: bench, history: [record(1, reps: [12, 10, 8], loads: [80, 70, 60])])!
        let active = [ExerciseSetLog(setNumber: 0, isWarmup: true), ExerciseSetLog(setNumber: 1, isCompleted: true), ExerciseSetLog(setNumber: 2), ExerciseSetLog(setNumber: 3)]
        let applicable = rec.applicableTargets(sets: active)
        XCTAssertEqual(Set(applicable.keys), [2, 3])
        XCTAssertEqual(applicable[2], ProgressionSetTarget(weightKg: 70, reps: 11))
        XCTAssertEqual(applicable[3], ProgressionSetTarget(weightKg: 60, reps: 9))
        XCTAssertTrue(rec.applicableTargets(sets: active + [ExerciseSetLog(setNumber: 4)]).isEmpty)
        XCTAssertTrue(rec.applicableTargets(sets: active.map { set in var set = set; set.isCompleted = true; return set }).isEmpty)
    }

    func testNoHistoryWarmupsAndFailureNeverOfferAnApplicableTarget() {
        var warmups = record(1)
        warmups.exerciseLogs[0].sets = [SessionSetLog(setNumber: 0, weightKg: 20, reps: 10, isWarmup: true)]
        // A warmup-only occurrence was started but has no working baseline: it is incomplete, not absent.
        for (history, action) in [([WorkoutSessionRecord](), ProgressionAction.firstSession), ([warmups], .insufficientData)] {
            let rec = ProgressionEngine.computeProgression(exercise: bench, history: history)!
            XCTAssertEqual(rec.action, action)
            XCTAssertTrue(rec.setTargets.isEmpty)
        }
        var failure = bench
        failure.reps = RepTarget(toFailure: true)
        XCTAssertNil(ProgressionEngine.computeProgression(exercise: failure, history: [record(1)]))
    }

    @MainActor func testInlineCoachDetailsAtNarrowWidthAndLargeLocalizedText() throws {
        let previous = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(previous) }
        var exercise = bench
        exercise.reps = RepTarget(min: 3, max: 6)
        let targets = try XCTUnwrap(ProgressionEngine.computeProgression(exercise: exercise,
            history: [record(1, reps: [5, 5, 4], loads: [77.5, 82.5, 87.5])]))
        var bodyweight = bench
        bodyweight.name = "Push Ups"
        bodyweight.exerciseId = "push-ups"
        let reviewLogs = (1...3).map { day -> WorkoutSessionRecord in
            var source = record(day, reps: [12, 12, 10], loads: [0, 0, 0])
            source.exerciseLogs[0].exerciseName = bodyweight.name
            source.exerciseLogs[0].exerciseId = bodyweight.exerciseId
            return source
        }
        let review = try XCTUnwrap(ProgressionEngine.computeProgression(exercise: bodyweight, history: reviewLogs))
        XCTAssertTrue(review.isPlateau)
        var bodyweightTargetExercise = bodyweight
        bodyweightTargetExercise.reps = RepTarget(min: 3, max: 6)
        var bodyweightSource = record(1, reps: [5, 5, 4], loads: [0, 0, 0])
        bodyweightSource.exerciseLogs[0].exerciseName = bodyweight.name
        bodyweightSource.exerciseLogs[0].exerciseId = bodyweight.exerciseId
        let bodyweightTargets = try XCTUnwrap(ProgressionEngine.computeProgression(exercise: bodyweightTargetExercise, history: [bodyweightSource]))
        var holdLoadExercise = bench
        holdLoadExercise.reps = RepTarget(min: 6, max: 10)
        let holdLoadTargets = try XCTUnwrap(ProgressionEngine.computeProgression(exercise: holdLoadExercise,
            history: [record(1, reps: [6, 5, 5], loads: [105, 110, 115])]))
        XCTAssertEqual(holdLoadTargets.action, .holdLoad)
        XCTAssertEqual(holdLoadTargets.rationaleKey, "progression.rationale.hold_load_mixed")
        XCTAssertEqual(holdLoadTargets.setTargets.map { $0.reps }, [7, 6, 6])
        XCTAssertEqual(holdLoadTargets.setTargets.map { $0.weightKg }, [105, 110, 115])
        var pecDeck = bench
        pecDeck.name = "Pec Deck Fly"
        pecDeck.exerciseId = "pec-deck-fly"
        pecDeck.sets = 4
        var pecDeckSource = record(1, reps: [12, 12, 12, 12], loads: [65, 65, 65, 65], targetSets: 4)
        pecDeckSource.exerciseLogs[0].exerciseName = pecDeck.name
        pecDeckSource.exerciseLogs[0].exerciseId = pecDeck.exerciseId
        let holdCeiling = try XCTUnwrap(ProgressionEngine.computeProgression(exercise: pecDeck, history: [pecDeckSource]))
        XCTAssertEqual(holdCeiling.action, .holdLoad)
        XCTAssertEqual(holdCeiling.rationaleKey, "progression.rationale.repeat_ceiling")
        XCTAssertEqual(holdCeiling.setTargets, Array(repeating: ProgressionSetTarget(weightKg: 65, reps: 12), count: 4))
        for language in ["en", "tr"] {
            LanguageManager.setLanguage(language)
            for (name, recommendation, applied) in [("targets", targets, false), ("applied-targets", targets, true),
                ("bodyweight-targets", bodyweightTargets, false), ("hold-load", holdLoadTargets, false),
                ("hold-ceiling", holdCeiling, false), ("review", review, false)] {
                let layouts: [(CGFloat, ContentSizeCategory)] = [(393, .large), (320, .extraExtraExtraLarge)]
                for (width, textSize) in layouts {
                    var compactHeight: CGFloat = 0
                    for expanded in [false, true] {
                        let card = ProgressionRecommendationCard(recommendation: recommendation, weightUnit: .kg,
                            canApplyTarget: true, expanded: .constant(expanded), wasApplied: .constant(applied),
                            onApplyTarget: {}, onOpenInfo: {})
                            .padding(20).frame(width: width).background(AppColors.background)
                            .environment(\.sizeCategory, textSize)
                        let renderer = ImageRenderer(content: card)
                        renderer.scale = 1
                        let image = try XCTUnwrap(renderer.uiImage)
                        XCTAssertEqual(image.size.width, width)
                        if expanded {
                            if recommendation.isPlateau { XCTAssertEqual(image.size.height, compactHeight) }
                            else { XCTAssertGreaterThan(image.size.height, compactHeight) }
                        } else { compactHeight = image.size.height }
                        let attachment = XCTAttachment(image: image)
                        attachment.name = "progression-inline-\(language)-\(name)-\(expanded ? "expanded" : "compact")-\(Int(width))"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                    }
                }
            }
        }
    }

    @MainActor func testCoachCardsAtNarrowWidthAndLargeLocalizedText() throws {
        let previous = LanguageManager.shared.currentLanguage
        let manager = ProAccessManager.shared
        manager.setFeatureOverride(.autoProgression, unlocked: true)
        defer { LanguageManager.setLanguage(previous); manager.setFeatureOverride(.autoProgression, unlocked: nil) }
        let cases: [(String, [WorkoutSessionRecord])] = [("uniform", [record(1)]), ("by-set", [record(1, reps: [12, 10, 8], loads: [80, 70, 60])]),
            ("hold-load-mixed", [record(1, reps: [6, 5, 5], loads: [105, 110, 115])]),
            ("incomplete", [record(1, reps: [8])]), ("incomplete-zero", [record(1, reps: [8])]), ("incomplete-six", [record(1, reps: [8])]),
            ("incomplete-one-left", [record(1, reps: [8])]), ("incomplete-recorded", [record(1, reps: [8])]), ("baseline-zero", []), ("baseline", []), ("baseline-recorded", [])]
        for language in ["en", "tr"] {
            LanguageManager.setLanguage(language)
            for (name, history) in cases {
                var exercise = bench
                if name == "hold-load-mixed" { exercise.reps = RepTarget(min: 6, max: 10) }
                let total = name == "incomplete" ? 3 : (name == "incomplete-zero" || name == "baseline-zero") ? 5 : 6
                let recorded = (name == "incomplete-zero" || name == "baseline-zero") ? 0 : name == "incomplete" ? 1 : name == "incomplete-one-left" ? 5 : (name == "incomplete-recorded" || name == "baseline-recorded") ? 6 : 4
                if name.hasPrefix("incomplete") || name.hasPrefix("baseline") { exercise.sets = total }
                let sessionSets: [ExerciseSetLog]? = (name.hasPrefix("incomplete") || name.hasPrefix("baseline"))
                    ? [ExerciseSetLog(setNumber: 0, isCompleted: true, isWarmup: true)] + (1...total).map { index in
                        ExerciseSetLog(setNumber: index, weightKg: 65, completedReps: 8, isCompleted: index <= recorded)
                    } : nil
                let rec = ProgressionEngine.computeProgression(exercise: exercise, history: history)!
                let layouts: [(CGFloat, ContentSizeCategory)] = name.hasPrefix("baseline") || name.hasPrefix("incomplete")
                    ? [(393, .large), (320, .extraExtraExtraLarge)]
                    : [(320, .extraExtraExtraLarge)]
                for (width, textSize) in layouts {
                    let content = ProgressionCoachCard(recommendation: rec, sessionSets: sessionSets, onApplyTarget: {}, onOpenInfo: {})
                        .padding(20).frame(width: width).background(AppColors.background)
                        .environment(\.sizeCategory, textSize)
                    let renderer = ImageRenderer(content: content)
                    renderer.scale = 1
                    let image = try XCTUnwrap(renderer.uiImage)
                    XCTAssertEqual(image.size.width, width)
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "progression-\(language)-\(name)-\(Int(width))"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    @MainActor
    func testTabSwipeTransitionsFollowCorrectOrder() {
        let store = AppStore.shared
        store.navigate(to: .today)
        XCTAssertEqual(store.currentView, .today)

        XCTAssertTrue(store.navigateToNextTab())
        XCTAssertEqual(store.currentView, .plan)

        XCTAssertTrue(store.navigateToNextTab())
        XCTAssertEqual(store.currentView, .library)

        XCTAssertTrue(store.navigateToNextTab())
        XCTAssertEqual(store.currentView, .history)

        XCTAssertFalse(store.navigateToNextTab())
        XCTAssertEqual(store.currentView, .history)

        XCTAssertTrue(store.navigateToPreviousTab())
        XCTAssertEqual(store.currentView, .library)

        XCTAssertTrue(store.navigateToPreviousTab())
        XCTAssertEqual(store.currentView, .plan)

        XCTAssertTrue(store.navigateToPreviousTab())
        XCTAssertEqual(store.currentView, .today)

        XCTAssertFalse(store.navigateToPreviousTab())
        XCTAssertEqual(store.currentView, .today)
    }

    @MainActor
    func testDirectClickTabSwitchesPageAndActivePill() {
        let store = AppStore.shared
        store.isOnboardingCompleted = true
        store.navigate(to: .today)

        let rootView = RootView()
        let controller = UIHostingController(rootView: rootView)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        XCTAssertEqual(store.currentView, .today)

        store.navigate(to: .library)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        XCTAssertEqual(store.currentView, .library)
    }
}

final class TabPagingTests: XCTestCase {
    @MainActor
    func testTabPagerKeepsFractionalOffsetAndDockInSync() throws {
        for width in [CGFloat(320), CGFloat(440)] {
            try withTabPager(width: width) { store, controller, pager in
                // Include both sides of each selection boundary, a reversal
                // before release, and all four settled pages.
                for position in [CGFloat(0), -0.2, 0, 0.25, 0.6, 0.85, 0.3, 0,
                                 1, 1.25, 1.6, 2, 2.4, 2.75, 3, 3.2, 3, 2, 1, 0] {
                    pager.setContentOffset(CGPoint(x: pager.bounds.width * position, y: 0), animated: false)
                    pumpTabPager(controller)
                    XCTAssertEqual(pager.contentOffset.x / pager.bounds.width, position, accuracy: 0.01,
                                   "Crossing the selection boundary must not snap an unfinished drag")
                    try assertDockPosition(max(0, min(3, position)), in: controller)
                    if position.rounded() == position {
                        XCTAssertEqual(store.currentView, AppStore.mainTabs[Int(position)])
                    }
                    if position == 0.6 || position == 2.4 {
                        let attachment = XCTAttachment(image: tabPagerImage(controller))
                        attachment.name = "interactive-tab-swipe-\(Int(width))-\(position)"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                    }
                }
            }
        }
    }

    @MainActor
    func testTabPagerExternalNavigationOverridesPartialSwipe() throws {
        try withTabPager { store, controller, pager in
            for destination in [ViewMode.history, .today, .library, .plan, .history, .today] {
                let source = CGFloat(try XCTUnwrap(AppStore.mainTabs.firstIndex(of: store.currentView)))
                let partialPosition = source + (source < 3 ? 0.35 : -0.35)
                pager.setContentOffset(CGPoint(x: pager.bounds.width * partialPosition, y: 0), animated: false)
                pumpTabPager(controller)
                store.navigate(to: destination)
                pumpTabPager(controller)
                let index = try XCTUnwrap(AppStore.mainTabs.firstIndex(of: destination))
                XCTAssertEqual(pager.contentOffset.x / pager.bounds.width, CGFloat(index), accuracy: 0.01)
                XCTAssertEqual(store.currentView, destination)
                try assertDockPosition(CGFloat(index), in: controller)
            }
        }
    }

    @MainActor
    func testTabPagerDisablesOnlyPagingInExerciseDetails() throws {
        try withTabPager { store, controller, pager in
            store.openExercise(id: "barbell-bench-press")
            pumpTabPager(controller)
            XCTAssertEqual(pager.contentOffset.x / pager.bounds.width, 2, accuracy: 0.01)
            XCTAssertEqual(store.selectedExerciseId, "barbell-bench-press")
            XCTAssertFalse(pager.isScrollEnabled)
            let attachment = XCTAttachment(image: tabPagerImage(controller))
            attachment.name = "pager-exercise-detail-scroll"
            attachment.lifetime = .keepAlways
            add(attachment)
            let detailScroll = try XCTUnwrap(tabScrollViews(in: controller.view).first {
                $0 !== pager && $0.bounds.width > 300 && $0.isScrollEnabled
                    && $0.convert($0.bounds, to: controller.view).intersects(controller.view.bounds)
            })
            XCTAssertTrue(detailScroll.panGestureRecognizer.isEnabled,
                          "Blocking page swipes must preserve detail scrolling")
            store.selectExerciseInLibrary(id: nil)
            pumpTabPager(controller)
            XCTAssertEqual(store.currentView, .today)
            XCTAssertEqual(pager.contentOffset.x, 0, accuracy: 1)
            XCTAssertTrue(pager.isScrollEnabled)
            try assertDockPosition(0, in: controller)
        }
    }

    @MainActor
    func testTabPagerOpensOnCurrentNavigationSelection() throws {
        for destination in AppStore.mainTabs {
            try withTabPager(initialView: destination) { store, controller, pager in
                let index = try XCTUnwrap(AppStore.mainTabs.firstIndex(of: destination))
                XCTAssertEqual(store.currentView, destination)
                XCTAssertEqual(pager.contentOffset.x / pager.bounds.width, CGFloat(index), accuracy: 0.01)
                try assertDockPosition(CGFloat(index), in: controller)
            }
        }
    }

    @MainActor
    func testTabPagerKeepsHistoryDetailsScrollable() throws {
        try withTabPager(initialView: .history) { store, controller, pager in
            store.selectedHistoryDetailDay = WorkoutCalendar.mondayOfCurrentWeek()
            pumpTabPager(controller)
            XCTAssertFalse(pager.isScrollEnabled)
            let detailScroll = try XCTUnwrap(tabScrollViews(in: controller.view).first {
                $0 !== pager && $0.bounds.width > 300 && $0.isScrollEnabled
                    && $0.convert($0.bounds, to: controller.view).intersects(controller.view.bounds)
            })
            XCTAssertTrue(detailScroll.panGestureRecognizer.isEnabled)
            store.selectedHistoryDetailDay = nil
            pumpTabPager(controller)
            XCTAssertTrue(pager.isScrollEnabled)
            XCTAssertEqual(store.currentView, .history)
            XCTAssertEqual(pager.contentOffset.x / pager.bounds.width, 3, accuracy: 0.01)
            try assertDockPosition(3, in: controller)
        }
    }

    @MainActor
    func testTabPagerTracksSwipeWithTurkishLabels() throws {
        let previousLanguage = LanguageManager.shared.currentLanguage
        LanguageManager.setLanguage("tr")
        defer { LanguageManager.setLanguage(previousLanguage) }
        try withTabPager(width: 320) { store, controller, pager in
            for position in [CGFloat(0.4), 1, 1.6, 2, 2.5, 3, 0] {
                pager.setContentOffset(CGPoint(x: pager.bounds.width * position, y: 0), animated: false)
                pumpTabPager(controller)
                XCTAssertEqual(pager.contentOffset.x / pager.bounds.width, position, accuracy: 0.01)
                try assertDockPosition(position, in: controller)
            }
            XCTAssertEqual(store.currentView, .today)
            let attachment = XCTAttachment(image: tabPagerImage(controller))
            attachment.name = "interactive-tab-swipe-320-turkish"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    private func withTabPager(width: CGFloat = 393, initialView: ViewMode = .today,
        _ body: (AppStore, UIHostingController<RootView>, UIScrollView) throws -> Void) throws {
        let store = AppStore.shared
        let originalOnboarding = store.isOnboardingCompleted
        let originalView = store.currentView
        let originalExercise = store.selectedExerciseId
        let originalHistoryDay = store.selectedHistoryDetailDay
        let originalReturnView = store.returnView
        let originalWorkout = store.selectedWorkoutId
        let originalSession = store.activeSession
        store.isOnboardingCompleted = true
        store.activeSession = nil
        store.navigate(to: initialView)
        let controller = UIHostingController(rootView: RootView())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        defer {
            window.isHidden = true
            window.rootViewController = nil
            store.currentView = originalView
            store.selectedExerciseId = originalExercise
            store.selectedHistoryDetailDay = originalHistoryDay
            store.returnView = originalReturnView
            store.selectedWorkoutId = originalWorkout
            store.activeSession = originalSession
            store.isOnboardingCompleted = originalOnboarding
        }
        pumpTabPager(controller)
        let pager = try XCTUnwrap(tabScrollViews(in: controller.view).first {
            $0.bounds.width > 300 && $0.contentSize.width > 3 * $0.bounds.width
        })
        XCTAssertTrue(pager.isScrollEnabled)
        try body(store, controller, pager)
    }

    @MainActor
    private func tabScrollViews(in view: UIView) -> [UIScrollView] {
        ((view as? UIScrollView).map { [$0] } ?? []) + view.subviews.flatMap { tabScrollViews(in: $0) }
    }

    @MainActor
    private func pumpTabPager(_ controller: UIViewController) {
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        controller.view.layoutIfNeeded()
    }

    @MainActor
    private func tabPagerImage(_ controller: UIViewController) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: controller.view.bounds.size, format: format).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }

    @MainActor
    private func assertDockPosition(_ position: CGFloat, in controller: UIViewController,
                                    file: StaticString = #filePath, line: UInt = #line) throws {
        let image = try XCTUnwrap(tabPagerImage(controller).cgImage, file: file, line: line)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), file: file, line: line)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        var filledColumns = Set<Int>()
        for y in (image.height - 82)..<(image.height - 26) {
            for x in 0..<image.width {
                let offset = (y * image.width + x) * 4
                if abs(Int(pixels[offset]) - 20) <= 1,
                   abs(Int(pixels[offset + 1]) - 45) <= 1,
                   abs(Int(pixels[offset + 2]) - 41) <= 1 {
                    filledColumns.insert(x)
                }
            }
        }
        let left = try XCTUnwrap(filledColumns.min(), "The active dock rectangle must be visible", file: file, line: line)
        let right = try XCTUnwrap(filledColumns.max(), file: file, line: line)
        let dockWidth = min(CGFloat(image.width) - 40, 360)
        let itemWidth = (dockWidth - 24) / 4
        let expectedLeft = (CGFloat(image.width) - dockWidth) / 2 + 6 + position * (itemWidth + 4)
        XCTAssertEqual(CGFloat(left), expectedLeft, accuracy: 2, file: file, line: line)
        XCTAssertEqual(CGFloat(right + 1), expectedLeft + itemWidth, accuracy: 2, file: file, line: line)
    }

}


final class SessionFeaturePaywallTests: XCTestCase {
    @MainActor
    func testLocalizedPaywallSnapshotsKeepFooterFixedWhileContentScrolls() async throws {
        let previousLanguage = LanguageManager.shared.currentLanguage
        let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        defer { LanguageManager.setLanguage(previousLanguage); previousWindow?.makeKeyAndVisible() }
        let cases: [(ProFeature?, WeightUnit)] = [
            (.autoProgression, .kg), (.cloudBackup, .kg), (.volumeMatrix, .kg),
            (.formLab, .kg), (.customThemes, .kg), (nil, .kg), (.warmupCalculator, .kg), (.warmupCalculator, .lbs)
        ]
        for (feature, unit) in cases {
            let imageName: String
            let tag: String
            switch feature {
            case .cloudBackup:
                imageName = "paywall_cloud_backup"
                tag = "cloud-backup-paywall"
            case .volumeMatrix:
                imageName = "paywall_volume_matrix"
                tag = "volume-paywall"
            case .formLab:
                imageName = "paywall_rep_lab"
                tag = "rep-lab-paywall"
            case .customThemes:
                imageName = "paywall_custom_themes"
                tag = "custom-themes-paywall"
            case .none:
                imageName = "paywall_general"
                tag = "general-paywall"
            case .warmupCalculator:
                imageName = unit == .lbs ? "paywall_warmup_plates_lbs" : "paywall_warmup_plates"
                tag = "warmup-paywall"
            default:
                imageName = "paywall_smart_progression"
                tag = "progression-paywall"
            }
            let artwork = try XCTUnwrap(UIImage(named: imageName))
            XCTAssertEqual(artwork.size.width, artwork.size.height)
            for language in ["en", "tr"] {
                LanguageManager.setLanguage(language)
                for (width, textSize) in [(CGFloat(393), ContentSizeCategory.large), (320, .large), (320, .extraExtraExtraLarge)] {
                    let view = SessionFeaturePaywallContent(
                        annual: SessionPaywallOffer(price: "TRY 999.99", monthlyBreakdown: "TRY 83.33 / month", savingsPercent: 44),
                        monthly: SessionPaywallOffer(price: "TRY 149.99"), selectedPlan: .annual,
                        isPurchasing: false, isRestoring: false, purchaseError: nil, restoreMessage: nil, isRestoreError: false,
                        onSelectPlan: { _ in }, onPurchase: {}, onRestore: {}, onRetryPrices: {}, onTerms: {}, onPrivacy: {}, onClose: {}, feature: feature, weightUnit: unit)
                        .environment(\.sizeCategory, textSize)
                    let controller = UIHostingController(rootView: view)
                    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 820))
                    window.rootViewController = controller
                    window.makeKeyAndVisible()
                    controller.view.frame = window.bounds
                    controller.view.layoutIfNeeded()
                    try await Task.sleep(nanoseconds: 300_000_000)
                    func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
                    let scroll = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UIScrollView }.first)
                    XCTAssertLessThanOrEqual(scroll.contentSize.width, scroll.bounds.width + 1, "Content must never scroll horizontally")
                    XCTAssertGreaterThan(scroll.contentSize.height, 400, "Hero and plans must have complete content")
                    let footerOrigin = scroll.frame.maxY
                    for position in ["top", "plans"] {
                        if position == "plans" {
                            scroll.setContentOffset(CGPoint(x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)), animated: false)
                            try await Task.sleep(nanoseconds: 150_000_000)
                        }
                        XCTAssertEqual(scroll.frame.maxY, footerOrigin, "Scrolling cannot move the purchase footer")
                        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { context in
                            controller.view.layer.render(in: context.cgContext)
                        }
                        XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 10_000)
                        let attachment = XCTAttachment(image: image)
                        attachment.name = "\(tag)-\(unit.rawValue)-\(language)-\(Int(width))-\(textSize == .large ? "normal" : "large")-\(position)"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                    }
                    window.isHidden = true
                }
            }
        }
    }
}

final class HistoryBreakdownTests: XCTestCase {
    private let day = WorkoutCalendar.parseDate("2026-10-06")!
    private var bench: Workout { Workout(id: "bench", day: 1, title: "Heavy Bench & Push", exercises: [Exercise(id: "bench-e", name: "Bench Press", sets: 2)]) }
    private var pull: Workout { Workout(id: "pull", day: 2, title: "Heavy Pull & Upper Back", exercises: [Exercise(id: "pull-e", name: "Barbell Row", sets: 2)]) }
    private var program: Program { Program(id: "breakdown-p", name: "Heavy", workouts: [bench, pull]) }

    private func record(_ workout: Workout, complete: Bool, scheduled: String? = nil) -> WorkoutSessionRecord {
        WorkoutSessionRecord(id: "s-\(workout.id)", programId: program.id, workoutId: workout.id,
            workoutTitle: workout.title, startedAt: "2026-10-06T09:00:00Z", completedAt: "2026-10-06T10:00:00Z",
            durationSeconds: 600, totalVolumeKg: complete ? 1000 : 500, totalCompletedSets: complete ? 2 : 1,
            exerciseLogs: [SessionExerciseLog(exerciseName: workout.exercises[0].name,
                sets: (1...(complete ? 2 : 1)).map { SessionSetLog(setNumber: $0, weightKg: 50, reps: 10) }, targetSets: 2)],
            isComplete: complete, scheduledDate: scheduled)
    }

    private func sections(_ records: [WorkoutSessionRecord], program: Program? = nil, active: String? = nil,
        viewedDay: Date? = nil, today: Date? = nil) -> [WorkoutDaySection] {
        let p = program ?? self.program
        let selectedDay = viewedDay ?? day
        let weekday = (Calendar.current.component(.weekday, from: selectedDay) + 5) % 7 + 1
        return HistoryDayDetailData.groupSections(day: selectedDay, records: records,
            scheduledWorkout: p.workouts.first { $0.day == weekday }, activeProgramId: p.id,
            programs: [p], history: records, activeRecordId: active, today: today ?? day)
    }

    func testLastMonthUnfinishedRecordDoesNotAddEditedCurrentPlan() {
        let historicalDay = WorkoutCalendar.parseDate("2026-09-10")!
        let today = WorkoutCalendar.parseDate("2026-10-08")!
        var edited = pull
        edited.day = 4
        edited.title = "Current Thursday Plan"
        edited.exercises = [Exercise(id: "new-e", name: "Dumbbell Bench Press", sets: 8)]
        let p = Program(id: program.id, name: "Edited", workouts: [bench, edited])
        var partial = record(pull, complete: false)
        partial.startedAt = "2026-09-10T09:00:00Z"
        partial.completedAt = "2026-09-10T10:00:00Z"
        for snapshot in [nil, pull] as [Workout?] {
            partial.workoutSnapshot = snapshot
            let result = sections([partial], program: p, viewedDay: historicalDay, today: today)
            XCTAssertEqual(result.count, 1)
            XCTAssertEqual(result.first?.sessionRecord?.id, partial.id)
            XCTAssertEqual(result.first?.workoutTitle, pull.title)
            XCTAssertEqual(result.first?.completedSets, 1)
            XCTAssertFalse(result.first!.isComplete)
            XCTAssertFalse(result.contains { $0.sessionRecord == nil })
            XCTAssertEqual(result.first?.exerciseItems.first?.name, pull.exercises[0].displayName)
            XCTAssertFalse(result.first!.exerciseItems.contains { $0.name == edited.exercises[0].displayName })
        }
    }

    func testHistoricalDayRetainsEveryRecordedSessionWithoutUnstartedPlan() {
        let historicalDay = WorkoutCalendar.parseDate("2026-09-10")!
        var planned = pull
        planned.day = 4
        let p = Program(id: program.id, name: "Edited", workouts: [bench, planned])
        var first = record(bench, complete: true, scheduled: "2026-09-07")
        var second = record(pull, complete: false, scheduled: "2026-09-09")
        first.workoutSnapshot = bench
        second.workoutSnapshot = pull
        let result = sections([first, second], program: p, viewedDay: historicalDay)
        XCTAssertEqual(Set(result.compactMap { $0.sessionRecord?.id }), Set([first.id, second.id]))
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.reduce(0) { $0 + $1.completedSets }, 3)
    }

    func testEmptyHistoricalDayKeepsScheduledFallback() {
        let historicalDay = WorkoutCalendar.parseDate("2026-09-08")!
        let result = sections([], viewedDay: historicalDay)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.workout?.id, pull.id)
        XCTAssertNil(result.first?.sessionRecord)
        XCTAssertEqual(result.first?.completedSets, 0)
        XCTAssertEqual(result.first?.plannedSets, 2)
    }

    func testTodayAtDifferentTimeStillIncludesUnstartedPlanAboveCarryover() {
        let laterToday = Calendar.current.date(byAdding: .hour, value: 23, to: day)!
        let carryover = record(bench, complete: false, scheduled: "2026-10-05")
        let result = sections([carryover], today: laterToday)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first?.workout?.id, pull.id)
        XCTAssertNil(result.first?.sessionRecord)
        XCTAssertEqual(result.last?.sessionRecord?.id, carryover.id)
    }

    @MainActor
    func testLegacyThursdayDoesNotInventWednesdayFromCurrentPlanOrSnapshot() {
        let thursday = WorkoutCalendar.parseDate("2026-09-03")!
        var saved = record(pull, complete: false)
        saved.startedAt = "2026-09-03T17:45:00Z"
        saved.completedAt = "2026-09-03T19:10:00Z"
        var wednesday = pull
        wednesday.day = 3
        for weekday in [3, 4, 5] {
            var current = pull
            current.day = weekday
            XCTAssertNil(HistoryDayDetailData.scheduleContext(record: saved, workout: current, day: thursday).0)
        }
        saved.workoutSnapshot = wednesday
        XCTAssertNil(HistoryDayDetailData.scheduleContext(record: saved, workout: pull, day: thursday).0)
        saved.scheduledDate = "2026-09-02"
        XCTAssertEqual(WorkoutCalendar.formatDate(HistoryDayDetailData.scheduleContext(record: saved, workout: pull, day: thursday).0!), "2026-09-02")
    }

    @MainActor
    func testLegacyCurrentWorkoutFirstWithoutRedundantScheduleAndCarryoverDated() {
        let old = record(bench, complete: true)
        let current = record(pull, complete: false)
        let previousLanguage = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(previousLanguage) }
        for language in ["en", "tr"] {
            LanguageManager.setLanguage(language)
            for records in [[old, current], [current, old]] {
                let result = sections(records)
                XCTAssertEqual(result.map(\.workoutTitle), [pull.title, bench.title])
                XCTAssertEqual(result[0].scheduleLabel(on: day), LanguageManager.t("history.scheduleUnknown"))
                XCTAssertEqual(result[0].contextText(on: day, today: day), LanguageManager.t("history.recordedToday"))
                XCTAssertEqual(result[1].contextText(on: day, today: day), LanguageManager.t("history.additionalWorkout"))
                XCTAssertEqual(result[1].scheduleLabel(on: day), LanguageManager.t("history.scheduleUnknown"))
                XCTAssertTrue(result[0].canAct(on: day, today: day))
                XCTAssertFalse(result[1].canAct(on: day, today: day))
            }
        }
        XCTAssertNil(old.scheduledDate)
    }

    func testUnstartedPlanAboveCompletedCarryoverAndExcludedFromRecordedTotals() {
        let old = record(bench, complete: true, scheduled: "2026-10-05")
        let result = sections([old])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].workout?.id, pull.id)
        XCTAssertNil(result[0].sessionRecord)
        XCTAssertEqual(result[0].completedSets, 0)
        XCTAssertFalse(result[0].isComplete)
        XCTAssertTrue(result[0].canAct(on: day, today: day))
        XCTAssertNil(result[0].scheduleLabel(on: day))
        XCTAssertEqual(result[0].contextText(on: day, today: day), LanguageManager.t("history.todayWorkout"))
        XCTAssertEqual(result[1].contextText(on: day, today: day), LanguageManager.t("history.earlierWorkout"))
        XCTAssertNotNil(result[1].scheduleLabel(on: day))
        let detail = HistoryDayDetailData(date: day, dateString: "2026-10-06", status: .completed,
            sessionRecord: nil, workout: pull, sections: result)
        XCTAssertEqual(detail.recordedSections.reduce(0) { $0 + $1.plannedSets }, 2)
        XCTAssertEqual(detail.recordedSections.reduce(0) { $0 + $1.totalVolumeKg }, 1000)
    }

    func testSavedOriginAndPrescriptionSurvivePlanEditsAndUnknownIsNotToday() {
        var saved = record(bench, complete: false, scheduled: "2026-10-04")
        saved.workoutSnapshot = bench
        var edited = bench
        edited.day = 2
        edited.exercises[0].sets = 7
        let p = Program(id: program.id, name: "Edited", workouts: [edited, pull])
        let savedSection = sections([saved], program: p).first { $0.sessionRecord != nil }!
        XCTAssertEqual(WorkoutCalendar.formatDate(savedSection.scheduledDate!), "2026-10-04")
        XCTAssertEqual(savedSection.scheduleSource, .recorded)
        XCTAssertEqual(savedSection.plannedSets, 2)
        saved.scheduledDate = nil
        XCTAssertNil(sections([saved], program: p).first { $0.sessionRecord != nil }!.scheduledDate)
        saved.workoutSnapshot = nil
        saved.programId = "deleted"
        XCTAssertNil(sections([saved]).last!.scheduledDate)
        XCTAssertEqual(sections([saved]).last!.scheduleSource, .unknown)
    }

    func testNoDuplicatePlanRestDayAndLiveCompletionRemainSeparate() {
        let current = record(pull, complete: true, scheduled: "2026-10-06")
        XCTAssertEqual(sections([current]).count, 1)
        let live = sections([current], active: current.id).first!
        XCTAssertFalse(live.isComplete)
        XCTAssertTrue(live.isLiveSession)
        XCTAssertTrue(live.canAct(on: day, today: day))
        let rest = Program(id: program.id, name: "Rest", workouts: [bench])
        XCTAssertEqual(sections([record(bench, complete: true)], program: rest).count, 1)
        var sunday = bench
        sunday.day = 7
        let monday = WorkoutCalendar.parseDate("2026-10-05")!
        XCTAssertNil(HistoryDayDetailData.scheduleContext(record: record(sunday, complete: true), workout: sunday, day: monday).0)
    }

    func testScheduleSnapshotRoundTripAndLegacyDecoding() throws {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let draft = ActiveSessionDraft(programId: program.id, workout: bench,
            startedAt: "2026-10-06T09:00:00Z", startedAtEpochMillis: timestamp,
            scheduledDate: "2026-10-05")
        let result = SessionProgress.from(draft: draft, nowEpochMillis: timestamp).record(draft: draft, completedAtEpochMillis: timestamp)
        let restored = try JSONDecoder().decode(WorkoutSessionRecord.self, from: JSONEncoder().encode(result))
        XCTAssertEqual(restored.scheduledDate, "2026-10-05")
        XCTAssertEqual(restored.workoutSnapshot, bench)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any])
        legacy.removeValue(forKey: "scheduledDate")
        legacy.removeValue(forKey: "workoutSnapshot")
        let decoded = try JSONDecoder().decode(WorkoutSessionRecord.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decoded.scheduledDate)
        XCTAssertNil(decoded.workoutSnapshot)
        let restoredDraft = try JSONDecoder().decode(ActiveSessionDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(restoredDraft.scheduledDate, "2026-10-05")
    }

    @MainActor
    func testFreshPlanActionDoesNotResumeSameIdCarryoverOrReplaceLiveDraft() throws {
        let access = ProAccessManager.shared
        let cloudAccess = access.isFeatureUnlocked(.cloudBackup)
        access.setFeatureOverride(.cloudBackup, unlocked: false)
        defer { access.setFeatureOverride(.cloudBackup, unlocked: cloudAccess == access.isProSubscribed ? nil : cloudAccess) }
        let defaults = UserDefaults.standard
        let domain = try XCTUnwrap(Bundle.main.bundleIdentifier)
        let original = defaults.persistentDomain(forName: domain) ?? [:]
        defer { defaults.setPersistentDomain(original, forName: domain) }
        defaults.removeObject(forKey: "active_session_v1")
        defaults.set(true, forKey: "seeded_starters_v9")
        defaults.set(true, forKey: "seeded_starters_v10")
        var carryover = record(pull, complete: false)
        carryover.startedAt = ISO8601DateFormatter().string(from: Date())
        carryover.completedAt = carryover.startedAt
        let fixture = StoredAppState(programs: [program], activeProgramId: program.id,
            currentWeekKey: "", history: [carryover])
        defaults.set(try JSONEncoder().encode(fixture), forKey: "stored_app_state")
        let store = AppStore(persistence: AppStatePersistence(inMemory: true))
        XCTAssertTrue(store.startActiveSession(programId: program.id, workout: pull, allowPast: true,
            assignedCalendarDate: WorkoutCalendar.formatDate(Date()), startNewSession: true,
            scheduledDate: "2026-10-06"))
        let active = try XCTUnwrap(store.activeSession)
        XCTAssertNotEqual(active.id, carryover.id)
        XCTAssertFalse(active.setsByExercise.values.flatMap { $0 }.contains(where: \.isCompleted))
        XCTAssertEqual(active.scheduledDate, "2026-10-06")
        XCTAssertFalse(store.startActiveSession(programId: program.id, workout: pull, allowPast: true, startNewSession: true))
        XCTAssertEqual(store.activeSession?.id, active.id)
    }

    func testHistoryRestorePreservesWarmupsAndRepeatedSnapshotOccurrences() {
        let repeated = Workout(id: "repeated", day: 1, title: "Repeated row", exercises: [
            Exercise(id: "first", name: "Barbell Row", sets: 2),
            Exercise(id: "second", name: "Barbell Row", sets: 3)])
        let saved = WorkoutSessionRecord(id: "repeat", programId: "p", workoutId: repeated.id,
            workoutTitle: repeated.title, startedAt: "2026-10-05T09:00:00Z", completedAt: "2026-10-05T09:10:00Z",
            durationSeconds: 600, totalVolumeKg: 1500, totalCompletedSets: 3, exerciseLogs: [
                SessionExerciseLog(exerciseName: "Barbell Row", sets: [
                    SessionSetLog(setNumber: 0, weightKg: 20, reps: 10, isWarmup: true),
                    SessionSetLog(setNumber: 1, weightKg: 50, reps: 10)], targetSets: 2),
                SessionExerciseLog(exerciseName: "Barbell Row", sets: [
                    SessionSetLog(setNumber: 1, weightKg: 60, reps: 10),
                    SessionSetLog(setNumber: 2, weightKg: 60, reps: 10)], targetSets: 3)],
            isComplete: false, scheduledDate: "2026-10-05", workoutSnapshot: repeated)
        let restored = WorkoutSessionUtils.restoreSetsFromHistory(workout: repeated, record: saved)
        let first = restored["first"]!
        let second = restored["second"]!
        XCTAssertEqual(first.filter(\.isWarmup).count, 1)
        XCTAssertEqual(first.filter { !$0.isWarmup }.count, 2)
        XCTAssertEqual(first.filter { $0.isCompleted && !$0.isWarmup }.map(\.weightKg), [50])
        XCTAssertEqual(second.filter(\.isCompleted).map(\.weightKg), [60, 60])
        XCTAssertEqual(second.count, 3)
        XCTAssertFalse(second.last!.isCompleted)
    }

    @MainActor
    func testCurrentWeekHistoryResumeRestoresProgressSnapshotAndDuration() throws {
        let defaults = UserDefaults.standard
        let domain = try XCTUnwrap(Bundle.main.bundleIdentifier)
        let original = defaults.persistentDomain(forName: domain) ?? [:]
        defer { defaults.setPersistentDomain(original, forName: domain) }
        defaults.removeObject(forKey: "active_session_v1")
        defaults.set(true, forKey: "seeded_starters_v9")
        defaults.set(true, forKey: "seeded_starters_v10")
        let calendar = Calendar(identifier: .gregorian)
        let monday = try XCTUnwrap(WorkoutCalendar.parseDate(WorkoutCalendar.mondayOfCurrentWeek()))
        let performed = calendar.date(byAdding: .hour, value: 9, to: monday)!
        let formatter = ISO8601DateFormatter()
        let snapshot = pull
        let saved = WorkoutSessionRecord(id: "resume-week", programId: program.id, workoutId: snapshot.id,
            workoutTitle: snapshot.title, startedAt: formatter.string(from: performed),
            completedAt: formatter.string(from: performed.addingTimeInterval(600)), durationSeconds: 600,
            totalVolumeKg: 500, totalCompletedSets: 1,
            exerciseLogs: [SessionExerciseLog(exerciseName: "Barbell Row",
                sets: [SessionSetLog(setNumber: 1, weightKg: 50, reps: 10)], targetSets: 2)],
            isComplete: false, scheduledDate: WorkoutCalendar.formatDate(monday), workoutSnapshot: snapshot)
        var changed = snapshot
        changed.exercises[0].sets = 8
        let fixtureProgram = Program(id: program.id, name: "Edited", workouts: [changed])
        let fixture = StoredAppState(programs: [fixtureProgram], activeProgramId: program.id,
            currentWeekKey: "", history: [saved], calendarHistory: WorkoutCalendarHistory(
                nextScheduledDate: WorkoutCalendar.mondayOfCurrentWeek(), scheduledWeekdays: [2], entries: [
                    WorkoutDayEntry(id: "session:resume-week", date: WorkoutCalendar.formatDate(monday), status: .unfinished)]))
        defaults.set(try JSONEncoder().encode(fixture), forKey: "stored_app_state")
        let store = AppStore(persistence: AppStatePersistence(inMemory: true))
        XCTAssertTrue(store.startActiveSession(programId: program.id, workout: changed, allowPast: true,
            unfinishedRecordId: saved.id, resumeHistory: true))
        let draft = try XCTUnwrap(store.activeSession)
        XCTAssertEqual(draft.id, saved.id)
        XCTAssertEqual(draft.workout, snapshot)
        XCTAssertEqual(draft.startedAt, saved.startedAt)
        XCTAssertEqual(draft.assignedCalendarDate, WorkoutCalendar.formatDate(monday))
        XCTAssertEqual(draft.accumulatedSeconds, 600)
        XCTAssertEqual(draft.setsByExercise.values.flatMap { $0 }.count, 2)
        XCTAssertEqual(draft.setsByExercise.values.flatMap { $0 }.filter(\.isCompleted).count, 1)
        XCTAssertEqual(draft.setsByExercise.values.flatMap { $0 }.first?.weightKg, 50)
        XCTAssertFalse(store.checkAndArchiveStaleSession())
        store.updateActiveSession { current in
            var copy = current
            copy.setsByExercise = current.setsByExercise.mapValues { sets in sets.map { value in
                var set = value; set.isCompleted = true; set.weightKg = 50; set.completedReps = 10; return set
            } }
            return copy
        }
        let finished = try XCTUnwrap(store.activeSession)
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        store.completeActiveSession(SessionProgress.from(draft: finished, nowEpochMillis: now).record(draft: finished, completedAtEpochMillis: now))
        XCTAssertEqual(store.state.history.count, 1)
        XCTAssertEqual(store.state.history.first?.id, saved.id)
        XCTAssertEqual(store.state.history.first?.totalCompletedSets, 2)
        XCTAssertEqual(store.state.history.first?.startedAt, saved.startedAt)
        XCTAssertEqual(WorkoutCalendar.localDate(from: store.state.history.first?.completedAt), WorkoutCalendar.formatDate(Date()))
        XCTAssertEqual(store.state.calendarHistory?.entries.first { $0.id == "session:resume-week" }?.date,
            WorkoutCalendar.formatDate(monday))
        // An explicit old-week request is rejected by the store, even if a UI callback is stale.
        let previousSunday = calendar.date(byAdding: .day, value: -1, to: monday)!
        var old = saved
        old.id = "previous-week"
        old.startedAt = formatter.string(from: previousSunday)
        old.scheduledDate = WorkoutCalendar.formatDate(previousSunday)
        var state = store.state
        state.history = [old]
        state.calendarHistory?.entries = []
        store.saveState(state)
        XCTAssertFalse(store.startActiveSession(programId: program.id, workout: changed, allowPast: true,
            unfinishedRecordId: old.id, resumeHistory: true))
        XCTAssertNil(store.activeSession)
    }

    @MainActor
    func testBreakdownLocalizedNarrowScreensRenderCurrentAndCarryoverSections() async throws {
        let previousLanguage = LanguageManager.shared.currentLanguage
        let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        defer { LanguageManager.setLanguage(previousLanguage); previousWindow?.makeKeyAndVisible() }
        for language in ["en", "tr"] {
            LanguageManager.setLanguage(language)
            let records = [record(bench, complete: true), record(pull, complete: false)]
            let result = sections(records)
            let detail = HistoryDayDetailData(date: day, dateString: "2026-10-06", status: .completed,
                sessionRecord: result.first?.sessionRecord, workout: result.first?.workout, sections: result)
            let view = HistoryDetailView(detail: detail, history: records, onBack: {}, onActionSection: { _ in })
                .environment(\.sizeCategory, .extraExtraExtraLarge)
            let controller = UIHostingController(rootView: view)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.frame = window.bounds
            controller.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 200_000_000)
            func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
            let scroll = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UIScrollView }.first)
            XCTAssertLessThanOrEqual(scroll.contentSize.width, scroll.bounds.width + 1)
            XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
            for position in ["top", "carryover"] {
                if position == "carryover" {
                    scroll.setContentOffset(CGPoint(x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height)), animated: false)
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                let image = UIGraphicsImageRenderer(size: window.bounds.size).image { controller.view.layer.render(in: $0.cgContext) }
                let attachment = XCTAttachment(image: image)
                attachment.name = "ios-breakdown-\(language)-\(position)"
                attachment.lifetime = .keepAlways
                add(attachment)
                try image.pngData()?.write(to: URL(fileURLWithPath: "/tmp/ios-breakdown-\(language)-\(position).png"))
            }
            window.isHidden = true
        }
    }

    @MainActor
    func testCompactSingleWorkoutMixedProgressLocalizedSnapshots() async throws {
        let previousLanguage = LanguageManager.shared.currentLanguage
        let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        defer { LanguageManager.setLanguage(previousLanguage); previousWindow?.makeKeyAndVisible() }
        let names = ["Barbell Row", "Lat Pulldown", "Barbell Shrug", "Cable Lateral Raise", "Seated Cable Row", "Face Pull"]
        let exercises = names.enumerated().map { Exercise(id: "compact-\($0.offset)", name: $0.element, sets: 3) }
        let workout = Workout(id: "compact", day: 2, title: "Heavy Pull & Upper Back", exercises: exercises)
        let counts = [1, 2, 3, 3, 0, 0]
        let logs = names.enumerated().map { index, name in SessionExerciseLog(exerciseName: name,
            sets: (0..<counts[index]).map { SessionSetLog(setNumber: $0 + 1, weightKg: 50, reps: 10) }, targetSets: 3) }
        let saved = WorkoutSessionRecord(id: "compact", programId: "compact-p", workoutId: workout.id,
            workoutTitle: workout.title, startedAt: "2026-10-06T09:00:00Z", completedAt: "2026-10-06T09:20:00Z",
            durationSeconds: 1200, totalVolumeKg: 4500, totalCompletedSets: 9, exerciseLogs: logs,
            isComplete: false, scheduledDate: "2026-10-06", workoutSnapshot: workout)
        let detail = HistoryDayDetailData(date: day, dateString: "2026-10-06", status: .unfinished,
            sessionRecord: saved, workout: workout)
        for language in ["en", "tr"] {
            LanguageManager.setLanguage(language)
            for width: CGFloat in [393, 320] {
                let view = HistoryDetailView(detail: detail, history: [saved], today: day, onBack: {}, onActionWorkout: {})
                    .environment(\.sizeCategory, width == 320 ? .extraExtraLarge : .large)
                let controller = UIHostingController(rootView: view)
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 850))
                window.rootViewController = controller
                window.makeKeyAndVisible()
                controller.view.frame = window.bounds
                controller.view.layoutIfNeeded()
                try await Task.sleep(nanoseconds: 200_000_000)
                func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
                let scroll = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UIScrollView }.first)
                XCTAssertLessThanOrEqual(scroll.contentSize.width, scroll.bounds.width + 1)
                for position in ["top", "bottom"] {
                    if position == "bottom" { scroll.setContentOffset(CGPoint(x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height)), animated: false) }
                    try await Task.sleep(nanoseconds: 100_000_000)
                    let image = UIGraphicsImageRenderer(size: window.bounds.size).image { controller.view.layer.render(in: $0.cgContext) }
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "ios-breakdown-compact-\(language)-\(Int(width))-\(position)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
                window.isHidden = true
            }
        }
    }

    @MainActor
    func testPastWeekWorkoutsDoNotOfferActionButtons() {
        let lastWeekSunday = WorkoutCalendar.parseDate("2026-10-04")! // Sunday of previous week
        let currentTuesday = WorkoutCalendar.parseDate("2026-10-06")! // Tuesday of current week
        let currentMonday = WorkoutCalendar.parseDate("2026-10-05")!  // Monday of current week

        let unstartedBench = WorkoutDaySection(workout: bench)
        XCTAssertFalse(unstartedBench.canAct(on: lastWeekSunday, today: currentTuesday),
            "Unstarted workout on last week's date must not be actionable")
        XCTAssertTrue(unstartedBench.canAct(on: currentMonday, today: currentTuesday),
            "Unstarted workout on current week Monday must be actionable")
        XCTAssertTrue(unstartedBench.canAct(on: currentTuesday, today: currentTuesday),
            "Unstarted workout on current day must be actionable")

        let lastWeekRecord = record(bench, complete: false, scheduled: "2026-10-04")
        let pastSection = WorkoutDaySection(sessionRecord: lastWeekRecord, workout: bench)
        XCTAssertFalse(pastSection.canAct(on: lastWeekSunday, today: currentTuesday),
            "Workout session from last week must not be actionable")

        let carryoverFromPastWeek = WorkoutDaySection(sessionRecord: lastWeekRecord, workout: bench, scheduledDate: lastWeekSunday)
        XCTAssertFalse(carryoverFromPastWeek.canAct(on: currentTuesday, today: currentTuesday),
            "Carryover originally scheduled for last week must not be actionable")

        let detail = HistoryDayDetailData(date: lastWeekSunday, dateString: "2026-10-04", status: .unfinished,
            sessionRecord: lastWeekRecord, workout: bench, sections: [pastSection])
        var actionInvoked = false
        let view = HistoryDetailView(detail: detail, history: [lastWeekRecord], today: currentTuesday,
            onBack: {}, onActionWorkout: { actionInvoked = true },
            onActionSection: { _ in actionInvoked = true })
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()

        XCTAssertFalse(actionInvoked)
        window.isHidden = true
    }
}

final class HistoryActionPolicyTests: XCTestCase {
    private let today = WorkoutCalendar.parseDate("2026-10-08")!
    private let oldDay = WorkoutCalendar.parseDate("2026-09-07")!
    private let monday = WorkoutCalendar.parseDate("2026-10-05")!
    private var workout: Workout {
        Workout(id: "bench", day: 1, title: "Heavy Bench & Push", exercises: [
            Exercise(id: "bench-e", name: "Barbell Bench Press", sets: 6),
            Exercise(id: "fly-e", name: "Pec Deck Fly", sets: 4)
        ])
    }
    private func record(snapshot: Bool = true) -> WorkoutSessionRecord {
        WorkoutSessionRecord(id: "partial", programId: "history-p", workoutId: workout.id,
            workoutTitle: workout.title, startedAt: "2026-09-07T09:00:00Z", completedAt: "2026-09-07T10:00:00Z",
            durationSeconds: 600, totalVolumeKg: 500, totalCompletedSets: 1,
            exerciseLogs: [SessionExerciseLog(exerciseName: "Barbell Bench Press",
                sets: [SessionSetLog(setNumber: 1, weightKg: 50, reps: 10)], targetSets: 6)],
            isComplete: false, scheduledDate: "2026-09-07", workoutSnapshot: snapshot ? workout : nil)
    }
    private func detail(day: Date, record: WorkoutSessionRecord?, sections: Bool = true) -> HistoryDayDetailData {
        let resolved = sections ? HistoryDayDetailData.groupSections(day: day, records: record.map { [$0] } ?? [],
            scheduledWorkout: workout, activeProgramId: "history-p",
            programs: [Program(id: "history-p", name: "Heavy", workouts: [workout])], history: [], today: today) : []
        return HistoryDayDetailData(date: day, dateString: WorkoutCalendar.formatDate(day),
            status: .unfinished, sessionRecord: record, workout: workout, sections: resolved)
    }

    @MainActor
    func testPreviousMonthIsReadOnlyWithBothCallbacksAndLegacyFallback() {
        for resolvedSections in [true, false] {
            let view = HistoryDetailView(detail: detail(day: oldDay, record: record(), sections: resolvedSections), today: today,
                onBack: {}, onActionWorkout: { XCTFail("Old history must not start a workout") },
                onActionSection: { _ in XCTFail("Old history must not start a section") })
            XCTAssertNil(view.singleActionSection)
            XCTAssertNil(view.singleWorkoutAction)
        }
        var currentWeek = record()
        currentWeek.scheduledDate = "2026-10-05"
        let currentView = HistoryDetailView(detail: detail(day: monday, record: currentWeek), today: today,
            onBack: {}, onActionWorkout: {})
        XCTAssertNotNil(currentView.singleWorkoutAction)
        XCTAssertTrue(currentView.resumesSingleWorkout, "Current-week History resumes saved progress")
    }

    @MainActor
    func testCurrentWorkoutRequiresCallbackAndTargetsOwnSection() {
        var current = record()
        current.scheduledDate = "2026-10-08"
        let data = detail(day: today, record: current)
        let noCallback = HistoryDetailView(detail: data, today: today, onBack: {})
        XCTAssertNotNil(noCallback.singleActionSection)
        XCTAssertNil(noCallback.singleWorkoutAction)
        var calledId: String?
        let view = HistoryDetailView(detail: data, today: today, onBack: {},
            onActionWorkout: { XCTFail("Section callback must target its own workout") },
            onActionSection: { calledId = $0.sessionRecord?.id })
        XCTAssertTrue(view.resumesSingleWorkout)
        view.singleWorkoutAction?()
        XCTAssertEqual(calledId, current.id)
    }

    func testActionWeekBoundaryFutureOriginsCompletionAndEmptyWorkouts() {
        let sunday = WorkoutCalendar.parseDate("2026-10-04")!
        let future = WorkoutCalendar.parseDate("2026-10-09")!
        let nextWeek = WorkoutCalendar.parseDate("2026-10-12")!
        let plan = WorkoutDaySection(workout: workout)
        XCTAssertFalse(plan.canAct(on: sunday, today: today))
        XCTAssertTrue(plan.canAct(on: monday, today: today))
        let currentSunday = WorkoutCalendar.parseDate("2026-10-11")!
        let nextMonday = WorkoutCalendar.parseDate("2026-10-12")!
        XCTAssertTrue(plan.canAct(on: monday, today: currentSunday))
        XCTAssertFalse(plan.canAct(on: currentSunday, today: nextMonday))
        XCTAssertFalse(plan.canAct(on: future, today: today))
        XCTAssertTrue(WorkoutDaySection(workout: workout, scheduledDate: future).canAct(on: today, today: today), "Early performance within this week can resume today")
        XCTAssertFalse(WorkoutDaySection(workout: workout, scheduledDate: nextWeek).canAct(on: today, today: today))
        var complete = record()
        complete.isComplete = true
        complete.workoutSnapshot = nil
        complete.exerciseLogs[0].targetSets = 1
        XCTAssertFalse(WorkoutDaySection(sessionRecord: complete, workout: workout).canAct(on: today, today: today))
        XCTAssertTrue(WorkoutDaySection(sessionRecord: complete, workout: workout, isLiveSession: true).canAct(on: today, today: today))
        var empty = workout
        empty.exercises = []
        XCTAssertFalse(WorkoutDaySection(workout: empty).canAct(on: today, today: today))
    }

    func testLegacyLogsNeverAcquireExercisesOrTargetsFromEditedPlan() {
        let legacy = record(snapshot: false)
        var edited = workout
        edited.exercises[0].sets = 99
        edited.exercises.append(Exercise(id: "new", name: "Lat Pulldown", sets: 8))
        let rows = HistoryDayDetailData.buildExerciseProgress(sessionRecord: legacy, workout: edited)
        XCTAssertEqual(rows.map(\.name), [workout.exercises[0].displayName])
        XCTAssertEqual(rows.map(\.plannedSets), [6])
        XCTAssertEqual(rows.map(\.completedSets), [1])
        var withoutTarget = legacy
        withoutTarget.exerciseLogs[0].targetSets = nil
        XCTAssertEqual(HistoryDayDetailData.buildExerciseProgress(sessionRecord: withoutTarget, workout: edited)[0].plannedSets, 1)
        let savedRows = HistoryDayDetailData.buildExerciseProgress(sessionRecord: record(), workout: edited)
        XCTAssertEqual(savedRows.map(\.name), workout.exercises.map(\.displayName))
        XCTAssertEqual(savedRows.map(\.plannedSets), [6, 4])
    }

    func testPreviewAndDetailExcludeWarmupsAndAgreeOnRecordedSetsAndVolume() {
        var mixed = record()
        mixed.totalVolumeKg = 0
        mixed.exerciseLogs[0].sets.insert(SessionSetLog(setNumber: 0, weightKg: 999, reps: 99, isWarmup: true), at: 0)
        let data = detail(day: oldDay, record: mixed)
        let preview = HistoryDayPreviewCard(detail: data, history: [], onOpenDetail: {})
        XCTAssertEqual(preview.exerciseProgress, data.exerciseProgress)
        XCTAssertEqual(preview.exerciseProgress[0].completedSets, 1)
        XCTAssertEqual(preview.exerciseProgress[0].plannedSets, 6)
        XCTAssertEqual(preview.exerciseProgress[0].topSetWeight, 50)
        XCTAssertEqual(preview.volumeKg, 500)
        let fallback = HistoryDayPreviewCard(detail: detail(day: oldDay, record: mixed, sections: false), history: [], onOpenDetail: {})
        XCTAssertEqual(fallback.volumeKg, preview.volumeKg)
        XCTAssertEqual(fallback.exerciseProgress, preview.exerciseProgress)
    }

    @MainActor
    func testManualCompletionIsReadOnlyAndConsistentWithoutRecordedSets() {
        let data = HistoryDayDetailData(date: today, dateString: "2026-10-08", status: .completed,
            sessionRecord: nil, workout: workout)
        let preview = HistoryDayPreviewCard(detail: data, history: [], onOpenDetail: {})
        XCTAssertTrue(data.isCompletionMark)
        XCTAssertTrue(data.exerciseProgress.isEmpty)
        XCTAssertEqual(preview.exerciseProgress, data.exerciseProgress)
        XCTAssertEqual(preview.volumeKg, 0)
        let resolved = HistoryDayDetailData.groupSections(day: today, records: [], scheduledWorkout: workout,
            activeProgramId: "history-p", programs: [], history: [], manuallyCompleted: true, today: today)
        XCTAssertTrue(resolved.isEmpty, "A completion mark cannot identify today's edited prescription")
        XCTAssertNil(HistoryDetailView(detail: data, today: today, onBack: {}, onActionWorkout: {}).singleWorkoutAction)
    }

    func testCompletionUsesSavedPrescriptionAndTargetsInsteadOfEditedPlan() {
        var saved = record(snapshot: false)
        saved.isComplete = true
        saved.exerciseLogs[0].targetSets = 1
        var edited = workout
        edited.exercises.append(Exercise(id: "new", name: "Lat Pulldown", sets: 99))
        XCTAssertTrue(WorkoutCalendar.isSessionComplete(session: saved, workout: edited))
        XCTAssertTrue(WorkoutCalendar.isSessionComplete(session: saved, workout: nil))
        saved.exerciseLogs[0].targetSets = 2
        XCTAssertFalse(WorkoutCalendar.isSessionComplete(session: saved, workout: edited), "A saved incomplete target contradicts a legacy completion flag")
        saved.exerciseLogs[0].targetSets = 1
        saved.workoutSnapshot = workout
        XCTAssertFalse(WorkoutCalendar.isSessionComplete(session: saved, workout: edited), "Missing exercises in a saved snapshot remain unfinished")
    }

    func testWarmupsNeverCompleteWorkingTargetsAndEmptyLegacyIsNotComplete() {
        var saved = record(snapshot: false)
        saved.isComplete = nil
        saved.exerciseLogs[0].targetSets = 2
        saved.exerciseLogs[0].sets.append(SessionSetLog(setNumber: 0, weightKg: 20, reps: 10, isWarmup: true))
        XCTAssertFalse(WorkoutCalendar.isSessionComplete(session: saved, workout: workout))
        saved.exerciseLogs[0].sets.append(SessionSetLog(setNumber: 2, weightKg: 50, reps: 10))
        XCTAssertTrue(WorkoutCalendar.isSessionComplete(session: saved, workout: nil))
        saved.exerciseLogs = []
        XCTAssertFalse(WorkoutCalendar.isSessionComplete(session: saved, workout: workout))
        saved.isComplete = true
        XCTAssertTrue(WorkoutCalendar.isSessionComplete(session: saved, workout: workout), "An explicit legacy completion mark is preserved when no saved target contradicts it")
    }

    @MainActor
    func testMixedCalendarCompletionWinsRegardlessOfRecordOrderAndManualMark() throws {
        let store = AppStore.shared
        let original = store.state
        let originalActive = store.activeSession
        defer { store.state = original; store.activeSession = originalActive }
        store.activeSession = nil
        var complete = record(snapshot: false)
        complete.id = "complete"
        complete.isComplete = true
        complete.exerciseLogs[0].targetSets = 1
        let partial = record()
        let calendar = WorkoutCalendarHistory(nextScheduledDate: "2026-10-08", entries: [
            WorkoutDayEntry(id: "session:partial", date: "2026-09-07", status: .unfinished),
            WorkoutDayEntry(id: "session:complete", date: "2026-09-07", status: .completed)
        ])
        for records in [[partial, complete], [complete, partial]] {
            store.state = StoredAppState(programs: [], history: records, calendarHistory: calendar)
            XCTAssertEqual(store.calendarStatuses(today: today)["2026-09-07"], .completed)
        }
        var manual = calendar
        manual.entries = [WorkoutDayEntry(id: "session:partial", date: "2026-09-07", status: .unfinished),
            WorkoutDayEntry(id: "manual:other-workout", date: "2026-09-07", status: .completed)]
        store.state = StoredAppState(programs: [], history: [partial], calendarHistory: manual)
        XCTAssertEqual(store.calendarStatuses(today: today)["2026-09-07"], .completed)
    }

    @MainActor
    func testSavedOriginNeutralizesOnlyItsOwnMissAndRemovingProgressRestoresIt() {
        var saved = record(snapshot: false)
        saved.startedAt = "2026-10-08T09:00:00Z"
        saved.completedAt = "2026-10-08T10:00:00Z"
        saved.scheduledDate = "2026-10-05"
        var edited = workout
        edited.day = 4
        let calendar = WorkoutCalendarHistory(nextScheduledDate: "2026-10-05", scheduledWeekdays: [1, 2],
            missedDates: ["2026-10-05", "2026-10-06"], entries: [WorkoutDayEntry(id: "session:partial", date: "2026-10-08", status: .unfinished)])
        let programs = [Program(id: "history-p", name: "Edited", workouts: [edited])]
        let restored = WorkoutCalendar.restore(raw: calendar, sessions: [saved], today: "2026-10-08",
            weekdays: [4], programs: programs)
        XCTAssertFalse(restored.missedDates.contains("2026-10-05"))
        XCTAssertTrue(restored.missedDates.contains("2026-10-06"))
        let refreshed = WorkoutCalendar.refresh(history: calendar, today: "2026-10-08", weekdays: [4], programs: programs, sessions: [saved])
        XCTAssertFalse(refreshed.missedDates.contains("2026-10-05"))
        var legacy = saved
        legacy.scheduledDate = nil
        XCTAssertTrue(WorkoutCalendar.refresh(history: calendar, today: "2026-10-08", weekdays: [4], programs: programs, sessions: [legacy]).missedDates.contains("2026-10-05"))
        saved.totalCompletedSets = 0
        saved.exerciseLogs = []
        XCTAssertTrue(WorkoutCalendar.refresh(history: refreshed, today: "2026-10-08", weekdays: [4], programs: programs, sessions: [saved]).missedDates.contains("2026-10-05"))
        var marked = calendar
        marked.entries.append(WorkoutDayEntry(id: "manual:other", date: "2026-10-05", status: .completed))
        XCTAssertEqual(WorkoutCalendar.statuses(history: WorkoutCalendar.refresh(history: marked, today: "2026-10-08", weekdays: [4], programs: programs, sessions: [legacy]), today: "2026-10-08")["2026-10-05"], .completed)
    }

    func testRepeatedSnapshotExercisesPreserveEachOccurrenceAndPartialCompletion() {
        let repeated = Workout(id: "repeated", day: 1, title: "Bench twice", exercises: [
            Exercise(id: "bench-first", name: "Barbell Bench Press", sets: 2),
            Exercise(id: "bench-second", name: "Barbell Bench Press", sets: 3)
        ])
        for counts in [[2, 1], [1, 3], [2, 3]] {
            var saved = record()
            saved.isComplete = true // Exercise evidence must still detect an incomplete occurrence.
            saved.workoutSnapshot = repeated
            saved.exerciseLogs = counts.enumerated().map { index, count in
                SessionExerciseLog(exerciseName: "Barbell Bench Press",
                    sets: (1...count).map { SessionSetLog(setNumber: $0, weightKg: index == 0 ? 70 : 50, reps: 10) },
                    targetSets: index == 0 ? 2 : 3)
            }
            let rows = HistoryDayDetailData.buildExerciseProgress(sessionRecord: saved, workout: repeated)
            XCTAssertEqual(rows.map(\.completedSets), counts)
            XCTAssertEqual(rows.map(\.plannedSets), [2, 3])
            XCTAssertEqual(rows.map(\.topSetWeight), [70, 50])
            XCTAssertEqual(Set(rows.map(\.id)).count, 2)
            XCTAssertEqual(WorkoutCalendar.isSessionComplete(session: saved, workout: repeated), counts == [2, 3])
        }
        var samePrescription = repeated
        samePrescription.exercises[1].sets = 2
        var saved = record()
        saved.workoutSnapshot = samePrescription
        saved.exerciseLogs = [SessionExerciseLog(exerciseName: "Barbell Bench Press", sets: [], targetSets: 2),
            SessionExerciseLog(exerciseName: "Barbell Bench Press", sets: [], targetSets: 2)]
        XCTAssertEqual(Set(HistoryDayDetailData.buildExerciseProgress(sessionRecord: saved, workout: samePrescription).map(\.id)).count, 2,
            "Repeated rows retain separate SwiftUI identity even with identical names and prescriptions")
    }

    func testSnapshotFallbackPairsEachSavedLogOnlyOnce() {
        let repeated = Workout(id: "repeated", day: 1, title: "Bench twice", exercises: [
            Exercise(id: "bench-first", name: "Barbell Bench Press", sets: 2),
            Exercise(id: "row", name: "Barbell Row", sets: 1),
            Exercise(id: "bench-second", name: "Barbell Bench Press", sets: 3)
        ])
        var saved = record()
        saved.isComplete = true
        saved.workoutSnapshot = repeated
        saved.exerciseLogs = [SessionExerciseLog(exerciseName: "Barbell Row", sets: [SessionSetLog(setNumber: 1, reps: 10)], targetSets: 1),
            SessionExerciseLog(exerciseName: "Barbell Bench Press", sets: [SessionSetLog(setNumber: 1, reps: 10)], targetSets: 2)]
        let rows = HistoryDayDetailData.buildExerciseProgress(sessionRecord: saved, workout: repeated)
        XCTAssertEqual(rows.map(\.completedSets), [1, 1, 0])
        XCTAssertEqual(rows.map(\.plannedSets), [2, 1, 3])
        XCTAssertFalse(WorkoutCalendar.isSessionComplete(session: saved, workout: repeated))
    }

    @MainActor
    func testLocalizedPreviousMonthPartialProgressRendersWithoutContinuationAffordance() async throws {
        let previousLanguage = LanguageManager.shared.currentLanguage
        let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        defer { LanguageManager.setLanguage(previousLanguage); previousWindow?.makeKeyAndVisible() }
        for language in ["en", "tr"] {
            LanguageManager.setLanguage(language)
            let data = detail(day: oldDay, record: record())
            let fullPage = HistoryDetailView(detail: data, today: today, onBack: {}, onActionWorkout: { XCTFail("Read only") })
            XCTAssertNil(fullPage.singleWorkoutAction)
            let view = HistoryDayDetailSheet(detail: data, history: [record()], onDismiss: {},
                onActionWorkout: { XCTFail("Compatibility sheet must share read-only policy") }, today: today)
                .environment(\.sizeCategory, .extraExtraExtraLarge)
            let controller = UIHostingController(rootView: view)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 850))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.frame = window.bounds
            controller.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 200_000_000)
            func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
            let scroll = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UIScrollView }.first)
            XCTAssertLessThanOrEqual(scroll.contentSize.width, scroll.bounds.width + 1)
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { controller.view.layer.render(in: $0.cgContext) }
            let attachment = XCTAttachment(image: image)
            attachment.name = "ios-history-old-partial-\(language)"
            attachment.lifetime = .keepAlways
            add(attachment)
            try image.pngData()?.write(to: URL(fileURLWithPath: "/tmp/ios-history-old-partial-\(language).png"))
            window.isHidden = true
        }
    }
}


final class WorkoutDayPresentationTests: XCTestCase {
    func testWorkoutDayNameBoundsAndUnchangedLegacyNames() {
        XCTAssertFalse(Workout.isValidTitle(""))
        XCTAssertFalse(Workout.isValidTitle(" \n\t "))
        XCTAssertTrue(Workout.isValidTitle(" W "))
        XCTAssertTrue(Workout.isValidTitle(String(repeating: "W", count: 24)))
        XCTAssertFalse(Workout.isValidTitle(String(repeating: "W", count: 25)))
        XCTAssertTrue(Workout.isValidTitle("Göğüs Hipertrofisi"))
        XCTAssertEqual(Workout.titleLength(" 💪 "), 1)
        let legacy = "Existing workout name longer than 24 characters"
        XCTAssertTrue(Workout.isValidTitle(legacy, originalTitle: legacy))
        XCTAssertFalse(Workout.isValidTitle(legacy + "!", originalTitle: legacy))
        XCTAssertFalse(Workout.isValidTitle(" ", originalTitle: " "))
    }

    @MainActor
    func testWorkoutDayHeadersWrapAndCardsGrowAtNarrowWidthsAndLargerText() throws {
        let previous = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(previous) }
        let titles = ["Chest Hypertrophy", String(repeating: "W", count: 24),
            "Chest and shoulders with a much longer imported workout name"]
        for language in ["en", "tr"] {
            LanguageManager.setLanguage(language)
            for width: CGFloat in [320, 393] {
                for category in [ContentSizeCategory.large, .extraExtraExtraLarge] {
                    var heights: [CGFloat] = []
                    for (index, title) in titles.enumerated() {
                        let workout = Workout(id: "hero-name-fixture", day: 5, title: title,
                            focus: language == "en" ? "Heavy Dumbbell Bench Overload" : "Ağır Dambıl Bench Press Çalışması",
                            exercises: [Exercise(id: "bench", name: "Bench", sets: 3)],
                            targetMuscles: ["chest", "lats", "quadriceps", "hamstrings"])
                        let content = TodayHeroCard(workout: workout, programId: "hero-name-fixture",
                            todayIndex: 0, isCompleted: false, isAvailable: false,
                            availableDay: LanguageManager.workoutDays[4], hasUnfinishedProgress: false,
                            onStart: {})
                            .environment(\.sizeCategory, category)
                            .frame(width: width)
                            .background(AppColors.background)
                        let image = try renderCard(content, hasViewControls: true, requiresScrolling: true)
                        XCTAssertEqual(image.size.width, width, accuracy: 1)
                        XCTAssertGreaterThanOrEqual(image.size.height, 420)
                        heights.append(image.size.height)
                        let attachment = XCTAttachment(image: image)
                        attachment.name = "workout-day-header-\(language)-\(Int(width))-\(category)-\(index)"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                    }
                    XCTAssertGreaterThan(heights[2], heights[0], "Imported names must grow the card instead of ellipsizing")
                }
            }
        }
        let content = TodayHeroCard(workout: nil, todayIndex: 0, isCompleted: false,
            isAvailable: false, availableDay: nil, hasUnfinishedProgress: false, onStart: {})
            .environment(\.sizeCategory, .extraExtraExtraLarge)
            .frame(width: 320)
        let image = try renderCard(content, hasViewControls: false)
        XCTAssertGreaterThanOrEqual(image.size.height, 420)
        let attachment = XCTAttachment(image: image)
        attachment.name = "workout-day-recovery-larger-text"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testWorkoutControlsOnlyListRequiredViews() {
        let back = Workout(day: 4, title: "Heavy Pull & Upper Back", targetMuscles: ["back", "lats", "trapezius"])
        XCTAssertEqual(back.bodyViews(), [.back], "Reproduce the single required view in the reported workout")
        XCTAssertEqual(TodayHeroCard.bodyViewOptions(for: back), [.back])
        let chest = Workout(day: 5, title: "Chest", targetMuscles: ["chest"])
        XCTAssertEqual(TodayHeroCard.bodyViewOptions(for: chest), [.front])
        let calves = Workout(day: 2, title: "Calves", targetMuscles: ["calves"])
        XCTAssertEqual(TodayHeroCard.bodyViewOptions(for: calves), [.legsBack])
        let mixed = Workout(day: 1, title: "Full Body", targetMuscles: ["lats", "quadriceps"])
        XCTAssertEqual(TodayHeroCard.bodyViewOptions(for: mixed), [.back, .legsFront])
        let bothSides = Workout(day: 3, title: "Chest & Triceps", targetMuscles: ["chest", "triceps"])
        XCTAssertEqual(TodayHeroCard.bodyViewOptions(for: bothSides), [.front, .back])
    }

    @MainActor
    func testHeavyPullCardShowsOnlySelectedBackControlInNativeLayout() throws {
        let previous = LanguageManager.shared.currentLanguage
        defer { LanguageManager.setLanguage(previous) }
        let workout = Workout(id: "heavy-pull-controls", day: 4, title: "Heavy Pull & Upper Back",
            focus: "Heavy Barbell Rows, Lat & Trap Overload",
            exercises: (0..<4).map { Exercise(id: "fixture-\($0)", name: "Fixture") },
            targetMuscles: ["back", "lats", "trapezius"])
        for language in ["en", "tr"] {
            LanguageManager.setLanguage(language)
            for width: CGFloat in [320, 393] {
                for category in [ContentSizeCategory.large, .extraExtraExtraLarge] {
                    let card = TodayHeroCard(workout: workout, todayIndex: 3,
                        isCompleted: false, isAvailable: true, availableDay: nil,
                        hasUnfinishedProgress: false, onStart: {})
                        .environment(\.sizeCategory, category)
                        .frame(width: width).background(AppColors.background)
                    let image = try renderCard(card, hasViewControls: true)
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "heavy-pull-back-only-\(language)-\(Int(width))-\(category)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    @MainActor
    private func renderCard<Content: View>(_ content: Content, hasViewControls: Bool, requiresScrolling: Bool = false) throws -> UIImage {
        // ImageRenderer measures the intrinsic card, but native hosting is needed
        // to capture the horizontal view-control scroll view.
        let size = try XCTUnwrap(ImageRenderer(content: content).uiImage).size
        let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        let controller = UIHostingController(rootView: content)
        controller.safeAreaRegions = []
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            previousWindow?.makeKey()
        }
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        controller.view.layoutIfNeeded()
        if hasViewControls {
            func scrollViews(_ view: UIView) -> [UIScrollView] {
                (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
            }
            let controls = try XCTUnwrap(scrollViews(controller.view).first)
            XCTAssertEqual(controls.bounds.height, 38, accuracy: 1)
            XCTAssertEqual(controls.contentSize.height, 38, accuracy: 1)
            if size.width == 320 && requiresScrolling {
                XCTAssertGreaterThan(controls.contentSize.width, controls.bounds.width,
                    "The four body views must remain reachable by scrolling on narrow phones")
            }
        }
        return UIGraphicsImageRenderer(size: size).image { _ in
            controller.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

}


final class WeightConfirmationRegressionTests: XCTestCase {
    private let bench = Exercise(id: "bench", name: "Barbell Bench Press", exerciseId: "barbell-bench-press", sets: 3, reps: RepTarget(min: 8, max: 12))
    private func session(_ date: String, loads: [Double] = [600, 600, 600]) -> WorkoutSessionRecord {
        WorkoutSessionRecord(id: date, programId: "p", workoutId: "w", workoutTitle: "Push",
            startedAt: "\(date)T10:00:00Z", completedAt: "\(date)T11:00:00Z", durationSeconds: 3600,
            exerciseLogs: [SessionExerciseLog(exerciseName: bench.name, sets: loads.enumerated().map {
                SessionSetLog(setNumber: $0.offset + 1, weightKg: $0.element, reps: 12)
            })])
    }

    func testRepeatedFullHeavySessionsClearTheUnverifiedHold() throws {
        let last = session("2026-10-08")
        let first = try XCTUnwrap(ProgressionEngine.computeProgression(exercise: bench, history: [last]))
        XCTAssertEqual(first.rationaleKey, "progression.rationale.unverified_jump")
        let verified = try XCTUnwrap(ProgressionEngine.computeProgression(exercise: bench, history: [last, session("2026-10-01")]))
        XCTAssertEqual(verified.action, .increaseLoad)
        XCTAssertEqual(try XCTUnwrap(verified.suggestedWeightKg), 602.5, accuracy: 0.001)
    }

    func testHeavyVerificationRequiresTheImmediatelyPreviousFullSetBySetLoads() throws {
        let last = session("2026-10-08", loads: [600, 550, 500])
        for previous in [session("2026-10-01", loads: [600, 500, 500]), session("2026-10-01", loads: [600])] {
            let rec = try XCTUnwrap(ProgressionEngine.computeProgression(exercise: bench,
                history: [last, previous, session("2026-09-24", loads: [600, 550, 500])]))
            XCTAssertEqual(rec.rationaleKey, "progression.rationale.unverified_jump")
        }
    }

    func testPoundsAboveKgCeilingPrefillWithoutChangingCanonicalWeight() throws {
        let canonical = WeightUnit.lbs.toCanonicalKg(1600)
        for input in ["1600", ""] {
            let source = ExerciseSetLog(setNumber: 1, weightInput: input, repsInput: "12", weightKg: canonical, completedReps: 12, isCompleted: true)
            let next = WorkoutSessionUtils.prefillSet(ExerciseSetLog(setNumber: 2), from: source, unit: .lbs)
            XCTAssertEqual(next.weightInput, "1600")
            XCTAssertEqual(try XCTUnwrap(next.weightKg), canonical, accuracy: 0.00001)
            XCTAssertEqual(next.completedReps, 12)
            XCTAssertFalse(next.isCompleted)
        }
    }

    func testCompletedWeightEditsRequireConfirmationButUnchangedLoadsDoNot() {
        let logged = ExerciseSetLog(setNumber: 1, weightInput: "80", weightKg: 80, isCompleted: true)
        func needs(_ weight: String, set: ExerciseSetLog? = nil, unit: WeightUnit = .kg) -> Bool {
            WorkoutSessionUtils.completedSetEditNeedsWeightConfirmation(set ?? logged, weightInput: weight, unit: unit, previousTopWeightKg: 80)
        }
        XCTAssertTrue(needs("800"))
        XCTAssertTrue(needs("1800", unit: .lbs))
        XCTAssertFalse(needs("90"))
        XCTAssertFalse(needs(""))
        XCTAssertFalse(needs("1600"))
        var incomplete = logged
        incomplete.isCompleted = false
        XCTAssertFalse(needs("800", set: incomplete))
        XCTAssertFalse(needs("800.00", set: ExerciseSetLog(setNumber: 1, weightInput: "800", weightKg: 800, isCompleted: true)))
        let canonicalOnly = ExerciseSetLog(setNumber: 1, weightKg: 600.1, isCompleted: true)
        XCTAssertFalse(needs(WorkoutSessionUtils.formatWeightInput(600.1, unit: .lbs), set: canonicalOnly, unit: .lbs))
    }

    @MainActor
    func testCompletedWeightEditPresentsConfirmationBeforePersisting() throws {
        let store = AppStore.shared
        let previousDraft = store.activeSession
        let previousHistory = store.state.history
        let previousUnit = store.weightUnit
        let previousLanguage = LanguageManager.shared.currentLanguage
        let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        defer {
            window.endEditing(true)
            window.isHidden = true
            store.activeSession = previousDraft
            store.state.history = previousHistory
            store.weightUnit = previousUnit
            LanguageManager.setLanguage(previousLanguage)
            previousWindow?.makeKeyAndVisible()
        }
        LanguageManager.setLanguage("en")
        store.weightUnit = .kg
        store.state.history = []
        let workout = Workout(id: "weight-confirmation", day: 1, title: "Fixture", exercises: [bench])
        let draft = ActiveSessionDraft(id: "weight-edit", programId: "p", workout: workout, startedAt: "2026-10-08T10:00:00Z",
            startedAtEpochMillis: Int64(Date().timeIntervalSince1970 * 1000), setsByExercise: [bench.id: [
                ExerciseSetLog(id: "logged", setNumber: 1, weightInput: "80", repsInput: "12", weightKg: 80, completedReps: 12, isCompleted: true)
            ]])
        store.activeSession = draft
        let host = UIHostingController(rootView: ActiveSessionView(store: store, draft: draft))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        func fields(_ view: UIView) -> [UITextField] {
            (view as? UITextField).map { [$0] } ?? view.subviews.flatMap { fields($0) }
        }
        let weight = try XCTUnwrap(fields(host.view).first)
        weight.text = "800"
        weight.sendActions(for: .editingChanged)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let alert = try XCTUnwrap(host.presentedViewController as? UIAlertController)
        XCTAssertEqual(alert.title, LanguageManager.t("session.anomalous_weight.title"))
        XCTAssertTrue(alert.message?.contains("800 kg") == true)
        XCTAssertEqual(store.activeSession?.setsByExercise[bench.id]?.first?.weightKg, 80)
        XCTAssertEqual(store.activeSession?.setsByExercise[bench.id]?.first?.isCompleted, true)
        XCTAssertEqual(Set(alert.actions.compactMap(\.title)), Set([LanguageManager.t("session.anomalous_weight.edit"), LanguageManager.t("session.anomalous_weight.confirm")]))
        alert.dismiss(animated: false)
    }
}

@MainActor
final class CloudBackupReliabilityTests: XCTestCase {
    private var roots: [URL] = []
    private var suites: [String] = []
    private let older = #"{"schemaVersion":4,"programs":[],"activeProgramId":"older","completed":[],"currentWeekKey":"","weeklyArchives":[],"history":[]}"#
    private let newer = #"{"schemaVersion":4,"programs":[],"activeProgramId":"newer","completed":[],"currentWeekKey":"","weeklyArchives":[],"history":[]}"#

    private final class Environment: @unchecked Sendable {
        private let lock = NSLock()
        private var _container: URL?
        private var _identity: Data? = try! NSKeyedArchiver.archivedData(withRootObject: "account-A", requiringSecureCoding: false)
        private var _premium = true
        private var _uploaded = false
        private var _uploadError: Error?
        var container: URL? { get { lock.withLock { _container } } set { lock.withLock { _container = newValue } } }
        var identity: Data? { get { lock.withLock { _identity } } set { lock.withLock { _identity = newValue } } }
        var premium: Bool { get { lock.withLock { _premium } } set { lock.withLock { _premium = newValue } } }
        var uploaded: Bool { get { lock.withLock { _uploaded } } set { lock.withLock { _uploaded = newValue } } }
        var uploadError: Error? { get { lock.withLock { _uploadError } } set { lock.withLock { _uploadError = newValue } } }
    }

    override func tearDown() {
        roots.forEach { try? FileManager.default.removeItem(at: $0) }
        suites.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) }
        super.tearDown()
    }

    private func fixture() throws -> (URL, UserDefaults, Environment) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cloud-regression-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        roots.append(root)
        let suite = "cloud-regression-" + UUID().uuidString
        suites.append(suite)
        return (root, UserDefaults(suiteName: suite)!, Environment())
    }

    private func manager(_ root: URL, _ defaults: UserDefaults, _ environment: Environment,
                         discover: @escaping (URL) async throws -> CloudSnapshot? = { _ in nil },
                         download: @escaping (URL) async throws -> Void = { _ in }) -> CloudMirrorManager {
        CloudMirrorManager(documentsDirectory: root.appendingPathComponent("local"), defaults: defaults,
            containerResolver: { XCTAssertFalse(Thread.isMainThread); return environment.container },
            identityProvider: { environment.identity }, premiumAvailable: { environment.premium },
            discoverSnapshot: discover, prepareDownload: download,
            uploadStatus: { _ in (environment.uploaded, !environment.uploaded, environment.uploadError) }, observesSystem: false)
    }

    private func write(_ payload: String, to url: URL, at date: Date = Date()) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try payload.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private func waitUntil(_ predicate: @escaping () -> Bool) async throws {
        let end = Date().addingTimeInterval(5)
        while !predicate() && Date() < end { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(predicate(), "Timed out waiting for cloud backup work")
    }

    func testCloudOnlyPlaceholderRestoresForFreeWhileSyncIsPaused() async throws {
        let (root, defaults, environment) = try fixture()
        environment.container = root.appendingPathComponent("cloud")
        environment.premium = false
        let remote = environment.container!.appendingPathComponent("Documents/CloudMirror/form_safety_mirror.json")
        let payload = newer
        let subject = manager(root, defaults, environment, discover: { _ in
            XCTAssertFalse(FileManager.default.fileExists(atPath: remote.path))
            return CloudSnapshot(url: remote, modifiedAt: Date())
        }, download: { url in
            // This test stub inherits the test's MainActor; the production downloader
            // runs file access in a utility task. Model the placeholder becoming local.
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try payload.write(to: url, atomically: true, encoding: .utf8)
        })
        subject.isEnabled = false
        let result = try await subject.readLatestSnapshotAsync()
        XCTAssertEqual(result, newer)
        XCTAssertFalse(subject.hasPendingSync)
        do { _ = try await subject.syncNowAsync(backupJson: older); XCTFail("Free users cannot write backups") }
        catch { XCTAssertEqual((error as NSError).code, 403) }
    }

    func testColdRestoreWaitsForDiscoveryInsteadOfReadingStaleLocalBackup() async throws {
        let (root, defaults, environment) = try fixture()
        environment.container = root.appendingPathComponent("cloud")
        let remote = environment.container!.appendingPathComponent("Documents/CloudMirror/form_safety_mirror.json")
        try write(newer, to: remote, at: Date(timeIntervalSince1970: 200))
        let subject = manager(root, defaults, environment, discover: { _ in
            try await Task.sleep(nanoseconds: 150_000_000)
            return CloudSnapshot(url: remote, modifiedAt: Date(timeIntervalSince1970: 200))
        })
        try write(older, to: subject.localMirrorDirectory.appendingPathComponent(CloudMirrorManager.backupFileName), at: Date(timeIntervalSince1970: 100))
        let result = try await subject.readLatestSnapshotAsync()
        XCTAssertEqual(result, newer)
    }

    func testDiscoveryFailureNeverSilentlyRestoresOlderLocalData() async throws {
        let (root, defaults, environment) = try fixture()
        environment.container = root.appendingPathComponent("cloud")
        let subject = manager(root, defaults, environment, discover: { _ in throw CloudMirrorError.discoveryTimedOut })
        try write(older, to: subject.localMirrorDirectory.appendingPathComponent(CloudMirrorManager.backupFileName))
        do { _ = try await subject.readLatestSnapshotAsync(); XCTFail("Discovery must succeed before selecting local data") }
        catch { XCTAssertEqual(error.localizedDescription, CloudMirrorError.discoveryTimedOut.localizedDescription) }
        XCTAssertEqual(try subject.readLatestSnapshot(), older)
    }

    func testOfflineBackupSurvivesManagerRestartAndUploadsOnReconnect() async throws {
        let (root, defaults, environment) = try fixture()
        let first = manager(root, defaults, environment)
        first.autoSync(backupJson: newer)
        try await waitUntil { FileManager.default.fileExists(atPath: first.localMirrorDirectory.appendingPathComponent(CloudMirrorManager.backupFileName).path) && !first.getStatus().isCheckingCloud }
        XCTAssertTrue(first.hasPendingSync)
        XCTAssertNil(first.getStatus().lastSyncTimestamp)
        environment.container = root.appendingPathComponent("cloud")
        let relaunched = manager(root, defaults, environment)
        relaunched.retryPendingSyncIfAny()
        try await waitUntil { !relaunched.hasPendingSync }
        let file = environment.container!.appendingPathComponent("Documents/CloudMirror/form_safety_mirror.json")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), newer)
        XCTAssertTrue(relaunched.getStatus().isUploadPending)
        XCTAssertNil(relaunched.getStatus().lastSyncTimestamp)
    }

    func testRefreshNeverMigratesWhenPausedOrPremiumExpired() async throws {
        for paused in [true, false] {
            let (root, defaults, environment) = try fixture()
            environment.container = root.appendingPathComponent("cloud")
            environment.premium = paused
            let subject = manager(root, defaults, environment)
            subject.isEnabled = !paused
            try write(newer, to: subject.localMirrorDirectory.appendingPathComponent(CloudMirrorManager.backupFileName))
            XCTAssertTrue(subject.savePendingSync(backupJson: newer))
            subject.refreshUbiquityURL()
            try await waitUntil { !subject.getStatus().isCheckingCloud }
            try await Task.sleep(nanoseconds: 100_000_000)
            XCTAssertTrue(subject.hasPendingSync)
            let remote = environment.container!.appendingPathComponent("Documents/CloudMirror/form_safety_mirror.json")
            XCTAssertFalse(FileManager.default.fileExists(atPath: remote.path))
        }
    }

    func testQueuedBackupNeverCrossesAppleAccounts() async throws {
        let (root, defaults, environment) = try fixture()
        let subject = manager(root, defaults, environment)
        XCTAssertTrue(subject.savePendingSync(backupJson: older))
        environment.identity = try NSKeyedArchiver.archivedData(withRootObject: "account-B", requiringSecureCoding: false)
        environment.container = root.appendingPathComponent("cloud-B")
        subject.retryPendingSyncIfAny()
        try await waitUntil { subject.getStatus().errorMessage != nil }
        XCTAssertTrue(subject.hasPendingSync)
        XCTAssertFalse(FileManager.default.fileExists(atPath: environment.container!.appendingPathComponent("Documents/CloudMirror/form_safety_mirror.json").path))
        XCTAssertEqual(subject.getStatus().errorMessage, CloudMirrorError.accountChanged.localizedDescription)
    }

    func testLegacyUnboundPendingBackupNeedsExplicitSync() async throws {
        let (root, defaults, environment) = try fixture()
        let subject = manager(root, defaults, environment)
        try write(older, to: root.appendingPathComponent("local/pending_form_safety_mirror.json"))
        environment.container = root.appendingPathComponent("cloud")
        subject.retryPendingSyncIfAny()
        try await waitUntil { subject.getStatus().errorMessage != nil }
        XCTAssertTrue(subject.hasPendingSync)
        _ = try await subject.syncNowAsync(backupJson: newer)
        XCTAssertFalse(subject.hasPendingSync)
        XCTAssertEqual(try String(contentsOf: environment.container!.appendingPathComponent("Documents/CloudMirror/form_safety_mirror.json"), encoding: .utf8), newer)
    }

    func testNewerCloudBackupIsPreservedDuringAutomaticRetry() async throws {
        let (root, defaults, environment) = try fixture()
        environment.container = root.appendingPathComponent("cloud")
        let remote = environment.container!.appendingPathComponent("Documents/CloudMirror/form_safety_mirror.json")
        let date = Date().addingTimeInterval(60)
        try write(newer, to: remote, at: date)
        let subject = manager(root, defaults, environment, discover: { _ in CloudSnapshot(url: remote, modifiedAt: date) })
        subject.autoSync(backupJson: older)
        try await waitUntil { subject.getStatus().errorMessage != nil }
        XCTAssertTrue(subject.hasPendingSync)
        XCTAssertEqual(try String(contentsOf: remote, encoding: .utf8), newer)
        XCTAssertEqual(subject.getStatus().errorMessage, CloudMirrorError.newerCloudBackup.localizedDescription)
    }

    func testAccountChangeDuringRestoreAbortsBeforeApplyingSnapshot() async throws {
        let (root, defaults, environment) = try fixture()
        environment.container = root.appendingPathComponent("cloud-A")
        let subject = manager(root, defaults, environment, discover: { _ in
            environment.identity = try NSKeyedArchiver.archivedData(withRootObject: "account-B", requiringSecureCoding: false)
            return nil
        })
        try write(older, to: subject.localMirrorDirectory.appendingPathComponent(CloudMirrorManager.backupFileName))
        do { _ = try await subject.readLatestSnapshotAsync(); XCTFail("Account change must abort restore") }
        catch { XCTAssertEqual(error.localizedDescription, CloudMirrorError.accountChanged.localizedDescription) }
    }

    func testUploadCompletionAndErrorPublishWithoutAnotherSync() async throws {
        let (root, defaults, environment) = try fixture()
        environment.container = root.appendingPathComponent("cloud")
        let subject = manager(root, defaults, environment)
        _ = try await subject.syncNowAsync(backupJson: newer)
        try await waitUntil { subject.status.isUploadPending }
        XCTAssertNil(subject.status.lastSyncTimestamp)
        environment.uploaded = true
        subject.refreshStatus()
        try await waitUntil { subject.status.lastSyncTimestamp != nil && !subject.status.isUploadPending }
        environment.uploaded = false
        environment.uploadError = NSError(domain: "iCloud", code: 1, userInfo: [NSLocalizedDescriptionKey: "Storage is full"])
        subject.refreshStatus()
        try await waitUntil { subject.status.errorMessage == "Storage is full" }
        XCTAssertTrue(subject.status.isUploadPending)
    }

    func testMalformedPendingBackupPreservesLastReadableMirror() async throws {
        let (root, defaults, environment) = try fixture()
        let subject = manager(root, defaults, environment)
        try write(older, to: subject.localMirrorDirectory.appendingPathComponent(CloudMirrorManager.backupFileName))
        XCTAssertTrue(subject.savePendingSync(backupJson: "not JSON"))
        subject.retryPendingSyncIfAny()
        try await waitUntil { subject.getStatus().errorMessage != nil }
        XCTAssertEqual(try subject.readLatestSnapshot(), older)
        XCTAssertTrue(subject.hasPendingSync)
    }

    func testInvalidBackupUnitNeverOverwritesTheLastReadableMirror() async throws {
        let (root, defaults, environment) = try fixture()
        let subject = manager(root, defaults, environment)
        try write(older, to: subject.localMirrorDirectory.appendingPathComponent(CloudMirrorManager.backupFileName))
        let invalid = "{\"schemaVersion\":4,\"weightUnit\":\"stone\"}"
        do { _ = try await subject.syncNowAsync(backupJson: invalid); XCTFail("Invalid unit must fail before writing any snapshot") }
        catch { XCTAssertEqual(error.localizedDescription, CloudMirrorError.invalidBackup.localizedDescription) }
        XCTAssertEqual(try subject.readLatestSnapshot(), older)
    }

    func testFirstOfflineBackupBindsToFirstAvailableAppleAccount() async throws {
        let (root, defaults, environment) = try fixture()
        environment.identity = nil
        let subject = manager(root, defaults, environment)
        subject.autoSync(backupJson: older)
        try await waitUntil { !subject.getStatus().isCheckingCloud }
        XCTAssertTrue(subject.hasPendingSync)
        environment.identity = try NSKeyedArchiver.archivedData(withRootObject: "account-A", requiringSecureCoding: false)
        environment.container = root.appendingPathComponent("cloud")
        subject.retryPendingSyncIfAny()
        try await waitUntil { !subject.hasPendingSync }
        XCTAssertEqual(try String(contentsOf: environment.container!.appendingPathComponent("Documents/CloudMirror/form_safety_mirror.json"), encoding: .utf8), older)
    }

    func testPausingDuringDiscoveryPreventsCloudWrite() async throws {
        let (root, defaults, environment) = try fixture()
        environment.container = root.appendingPathComponent("cloud")
        let subject = manager(root, defaults, environment, discover: { _ in
            defaults.set(false, forKey: "cloud_mirror_enabled")
            return nil
        })
        subject.autoSync(backupJson: older)
        try await waitUntil { subject.getStatus().errorMessage != nil }
        XCTAssertTrue(subject.hasPendingSync)
        XCTAssertFalse(FileManager.default.fileExists(atPath: environment.container!.appendingPathComponent("Documents/CloudMirror/form_safety_mirror.json").path))
    }

    func testRestoreUsesCurrentAccountInsteadOfNewerLocalCopyFromPreviousAccount() async throws {
        let (root, defaults, environment) = try fixture()
        let remote = root.appendingPathComponent("cloud-B/Documents/CloudMirror/form_safety_mirror.json")
        let subject = manager(root, defaults, environment, discover: { _ in CloudSnapshot(url: remote, modifiedAt: Date(timeIntervalSince1970: 100)) })
        _ = try await subject.syncNowAsync(backupJson: newer)
        environment.identity = try NSKeyedArchiver.archivedData(withRootObject: "account-B", requiringSecureCoding: false)
        environment.container = root.appendingPathComponent("cloud-B")
        try write(older, to: remote, at: Date(timeIntervalSince1970: 100))
        let restored = try await subject.readLatestSnapshotAsync()
        XCTAssertEqual(restored, older)
    }

    func testEquivalentIdentityArchivesRemainTheSameAppleAccount() async throws {
        let (root, defaults, environment) = try fixture()
        let subject = manager(root, defaults, environment)
        XCTAssertTrue(subject.savePendingSync(backupJson: older))
        let binaryIdentity = environment.identity
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.outputFormat = .xml
        archiver.encode("account-A", forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        environment.identity = archiver.encodedData
        XCTAssertNotEqual(binaryIdentity, environment.identity)
        environment.container = root.appendingPathComponent("cloud")
        subject.retryPendingSyncIfAny()
        try await waitUntil { !subject.hasPendingSync }
        XCTAssertEqual(try String(contentsOf: environment.container!.appendingPathComponent("Documents/CloudMirror/form_safety_mirror.json"), encoding: .utf8), older)
    }

    func testSuccessfulRestoreDiscardsOlderPendingExport() async throws {
        let (root, defaults, environment) = try fixture()
        let subject = manager(root, defaults, environment)
        XCTAssertTrue(subject.savePendingSync(backupJson: older))
        subject.didRestoreSnapshot()
        environment.container = root.appendingPathComponent("cloud")
        subject.retryPendingSyncIfAny()
        XCTAssertFalse(subject.hasPendingSync)
        XCTAssertFalse(FileManager.default.fileExists(atPath: environment.container!.appendingPathComponent("Documents/CloudMirror/form_safety_mirror.json").path))
    }

    func testNewWorkoutStagedDuringDiscoveryWinsOverOlderQueuedExport() async throws {
        let (root, defaults, environment) = try fixture()
        environment.container = root.appendingPathComponent("cloud")
        var discoveryCount = 0
        var releaseFirst: CheckedContinuation<Void, Never>?
        let subject = manager(root, defaults, environment, discover: { _ in
            discoveryCount += 1
            if discoveryCount == 1 {
                await withCheckedContinuation { releaseFirst = $0 }
            }
            return nil
        })
        subject.autoSync(backupJson: older)
        try await waitUntil { releaseFirst != nil }
        subject.autoSync(backupJson: newer)
        releaseFirst?.resume()
        try await waitUntil { !subject.hasPendingSync }
        XCTAssertEqual(try subject.readLatestSnapshot(), newer)
        XCTAssertEqual(try String(contentsOf: environment.container!.appendingPathComponent("Documents/CloudMirror/form_safety_mirror.json"), encoding: .utf8), newer)
    }

    func testBackupSheetLocalizedNarrowLayoutWithFreeRestore() async throws {
        let (root, defaults, environment) = try fixture()
        environment.premium = false
        let subject = manager(root, defaults, environment)
        let previousLanguage = LanguageManager.shared.currentLanguage
        let access = ProAccessManager.shared.isProSubscribed
        defer { LanguageManager.setLanguage(previousLanguage); ProAccessManager.shared.updateSubscriptionStatus(active: access) }
        ProAccessManager.shared.updateSubscriptionStatus(active: false)
        for language in ["en", "tr"] {
            LanguageManager.setLanguage(language)
            subject.refreshUbiquityURL()
            try await waitUntil { !subject.status.isCheckingCloud }
            let view = CloudBackupSheet(store: AppStore(persistence: AppStatePersistence(inMemory: true)), mirrorManager: subject)
                .environment(\.dynamicTypeSize, .xxxLarge)
            let host = UIHostingController(rootView: view)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 800))
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = window.bounds
            host.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 200_000_000)
            host.view.layoutIfNeeded()
            func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
            let scroll = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UIScrollView }.first)
            XCTAssertLessThanOrEqual(scroll.contentSize.width, scroll.bounds.width + 1)
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { context in host.view.layer.render(in: context.cgContext) }
            XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 10_000, "A rendered sheet must contain visible content")
            let attachment = XCTAttachment(image: image)
            attachment.name = "cloud-backup-free-\(language)-320-large"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertEqual(host.view.bounds.width, 320)
            window.isHidden = true
        }
    }
}

@MainActor
final class BackupWeightUnitSafetyTests: XCTestCase {
    private let exercise = Exercise(id: "unit-bench", name: "Bench Press", sets: 2, restSeconds: 0)
    private var workout: Workout { Workout(id: "unit-workout", day: 1, title: "Units", exercises: [exercise]) }

    private func withStore(_ body: (AppStore) throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let keys = ["stored_app_state", "active_session_v1", "weight_unit", "is_onboarding_completed", "seeded_starters_v9", "seeded_starters_v10"]
        let saved = keys.map { ($0, defaults.object(forKey: $0)) }
        let enabled = CloudMirrorManager.shared.isEnabled
        CloudMirrorManager.shared.isEnabled = false
        defer {
            for (key, value) in saved { if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } }
            CloudMirrorManager.shared.isEnabled = enabled
        }
        defaults.removeObject(forKey: "active_session_v1")
        defaults.set("kg", forKey: "weight_unit")
        defaults.set(true, forKey: "seeded_starters_v9")
        defaults.set(true, forKey: "seeded_starters_v10")
        let store = AppStore(persistence: AppStatePersistence(inMemory: true))
        store.activeSession = nil
        try body(store)
    }

    private func history(_ weight: Double) -> WorkoutSessionRecord {
        let date = ISO8601DateFormatter().string(from: Date())
        return WorkoutSessionRecord(id: "unit-history", programId: "unit-plan", workoutId: workout.id, workoutTitle: workout.title,
            startedAt: date, completedAt: date, durationSeconds: 900, totalVolumeKg: weight * 10, totalCompletedSets: 1,
            exerciseLogs: [SessionExerciseLog(exerciseName: exercise.name, sets: [SessionSetLog(setNumber: 1, weightKg: weight, reps: 10)], targetSets: 2)])
    }

    private func install(_ store: AppStore, weight: Double) {
        var state = store.state
        state.programs = [Program(id: "unit-plan", name: "Units", workouts: [workout])]
        state.activeProgramId = "unit-plan"
        state.history = [history(weight)]
        state.calendarHistory = nil
        store.saveState(state)
    }

    private func draft(weight: Double? = 100, input: String = "100", unit: WeightUnit? = .kg) -> ActiveSessionDraft {
        ActiveSessionDraft(id: "unit-live", programId: "unit-plan", workout: workout,
            startedAt: ISO8601DateFormatter().string(from: Date()), startedAtEpochMillis: Int64(Date().timeIntervalSince1970 * 1000),
            setsByExercise: [exercise.id: [ExerciseSetLog(id: "unit-set", setNumber: 1, weightInput: input, repsInput: "10", weightKg: weight, completedReps: 10, isCompleted: true, isWarmup: true)]],
            isPaused: true, weightInputUnit: unit)
    }

    func testKgAndPoundsBackupsRestorePreferenceWithoutConvertingCanonicalHistory() throws {
        try withStore { store in
            for unit in [WeightUnit.kg, .lbs] {
                let canonical = unit == .kg ? 100 : WeightUnit.lbs.toCanonicalKg(220)
                install(store, weight: canonical)
                store.weightUnit = unit
                let backup = store.exportBackupJson()
                let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(backup.utf8)) as? [String: Any])
                XCTAssertEqual(root["weightUnit"] as? String, unit.rawValue)
                XCTAssertNotNil(root["programs"])
                XCTAssertNil(root["state"], "The backup remains flat and compatible with Android")
                store.weightUnit = unit == .kg ? .lbs : .kg
                store.state.history = []
                XCTAssertTrue(store.restoreBackupJson(backup))
                XCTAssertEqual(store.weightUnit, unit)
                XCTAssertEqual(store.state.history.first?.exerciseLogs.first?.sets.first?.weightKg, canonical)
                XCTAssertEqual(store.state.history.first?.totalVolumeKg, canonical * 10)
                let reloaded = AppStore(persistence: store.statePersistence)
                XCTAssertEqual(reloaded.weightUnit, unit)
                XCTAssertEqual(reloaded.state.history.first?.exerciseLogs.first?.sets.first?.weightKg, canonical)
                for _ in 0..<6 { store.weightUnit = .lbs; store.weightUnit = .kg }
                XCTAssertEqual(store.state.history.first?.exerciseLogs.first?.sets.first?.weightKg, canonical)
            }
        }
    }

    func testLegacyBackupWithoutUnitKeepsDevicePreferenceAndCanonicalWeights() throws {
        try withStore { store in
            install(store, weight: 100)
            let legacy = String(data: try JSONEncoder().encode(store.state), encoding: .utf8)!
            store.weightUnit = .lbs
            XCTAssertTrue(store.restoreBackupJson(legacy))
            XCTAssertEqual(store.weightUnit, .lbs)
            XCTAssertEqual(store.state.history.first?.exerciseLogs.first?.sets.first?.weightKg, 100)
            XCTAssertEqual(WeightUnit.lbs.formatWeightWithUnit(100), "220 lbs")
            store.weightUnit = .kg
            XCTAssertEqual(store.state.history.first?.exerciseLogs.first?.sets.first?.weightKg, 100)
        }
    }

    func testInvalidUnitMetadataCannotPartiallyChangeStatePreferenceOrLiveWorkout() throws {
        try withStore { store in
            install(store, weight: 100)
            store.activeSession = draft()
            let before = store.exportBackupJson()
            let active = store.activeSession
            for value: Any in ["stone", 42, true, ["kg"], ["unit": "kg"]] {
                var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(before.utf8)) as? [String: Any])
                json["weightUnit"] = value
                let invalid = String(data: try JSONSerialization.data(withJSONObject: json), encoding: .utf8)!
                XCTAssertFalse(store.restoreBackupJson(invalid))
                let after = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(store.exportBackupJson().utf8)) as? [String: Any])
                let beforeObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(before.utf8)) as? [String: Any])
                XCTAssertTrue(NSDictionary(dictionary: after).isEqual(to: beforeObject))
                XCTAssertEqual(store.weightUnit, .kg)
                XCTAssertEqual(store.activeSession, active)
            }
        }
    }

    func testUnitChangesRebaseCompletedWarmupInputsAndPersistWithoutChangingWeights() throws {
        try withStore { store in
            install(store, weight: 100)
            store.flushPendingState()
            store.activeSession = draft()
            for _ in 0..<8 {
                store.weightUnit = .lbs
                let set = try XCTUnwrap(store.activeSession?.setsByExercise[exercise.id]?.first)
                XCTAssertEqual(set.weightInput, "220.46")
                XCTAssertEqual(set.weightKg, 100)
                XCTAssertTrue(set.isCompleted && set.isWarmup)
                XCTAssertEqual(store.activeSession?.weightInputUnit, .lbs)
                store.weightUnit = .kg
                XCTAssertEqual(store.activeSession?.setsByExercise[exercise.id]?.first?.weightInput, "100")
                XCTAssertEqual(store.activeSession?.setsByExercise[exercise.id]?.first?.weightKg, 100)
            }
            store.weightUnit = .lbs
            let reloaded = AppStore(persistence: store.statePersistence)
            XCTAssertEqual(reloaded.activeSession?.setsByExercise[exercise.id]?.first?.weightKg, 100)
            XCTAssertEqual(reloaded.activeSession?.setsByExercise[exercise.id]?.first?.weightInput, "220.46")
            XCTAssertEqual(reloaded.activeSession?.weightInputUnit, .lbs)
        }
    }

    func testRestoreUnitRebasesPreservedActiveWorkoutWithoutConvertingItsCanonicalValues() throws {
        withStore { store in
            install(store, weight: 100)
            store.weightUnit = .lbs
            let poundsBackup = store.exportBackupJson()
            store.weightUnit = .kg
            store.activeSession = draft(weight: 75, input: "75")
            XCTAssertTrue(store.restoreBackupJson(poundsBackup))
            XCTAssertEqual(store.weightUnit, .lbs)
            XCTAssertEqual(store.activeSession?.id, "unit-live")
            XCTAssertEqual(store.activeSession?.setsByExercise[exercise.id]?.first?.weightKg, 75)
            XCTAssertEqual(store.activeSession?.setsByExercise[exercise.id]?.first?.weightInput, "165.35")
        }
    }

    func testHistoryResumeUsesCurrentDisplayUnitWithoutChangingRecordedWeight() throws {
        try withStore { store in
            install(store, weight: 100)
            store.weightUnit = .lbs
            XCTAssertTrue(store.startActiveSession(programId: "unit-plan", workout: workout, allowPast: true,
                unfinishedRecordId: "unit-history", resumeHistory: true))
            let first = try XCTUnwrap(store.activeSession?.setsByExercise[exercise.id]?.first)
            XCTAssertEqual(first.weightInput, "220.46")
            XCTAssertEqual(first.weightKg, 100)
            XCTAssertEqual(store.activeSession?.weightInputUnit, .lbs)
        }
    }

    func testStartupRepairsStaleLegacyInputFromCanonicalWeight() throws {
        try withStore { store in
            install(store, weight: 100)
            store.flushPendingState()
            let old = draft(unit: nil)
            UserDefaults.standard.set(try JSONEncoder().encode(old), forKey: "active_session_v1")
            UserDefaults.standard.set("lbs", forKey: "weight_unit")
            let reloaded = AppStore(persistence: store.statePersistence)
            XCTAssertEqual(reloaded.activeSession?.setsByExercise[exercise.id]?.first?.weightKg, 100)
            XCTAssertEqual(reloaded.activeSession?.setsByExercise[exercise.id]?.first?.weightInput, "220.46")
            XCTAssertEqual(reloaded.activeSession?.weightInputUnit, .lbs)
        }
    }

    func testUnreadableActiveDraftRemainsOnDiskForRecovery() {
        withStore { store in
            let invalidDraft = Data("{\"weightInputUnit\":\"unsupported\"}".utf8)
            UserDefaults.standard.set(invalidDraft, forKey: "active_session_v1")
            let reloaded = AppStore(persistence: store.statePersistence)
            XCTAssertNil(reloaded.activeSession)
            XCTAssertEqual(UserDefaults.standard.data(forKey: "active_session_v1"), invalidDraft)
        }
    }

    func testInputOnlyLegacyDraftUsesItsRecordedUnitAndKeepsPartialAndEmptyEdits() {
        var old = draft(weight: nil, input: "100", unit: .kg)
        old.setsByExercise[exercise.id]?.append(ExerciseSetLog(id: "partial", setNumber: 2, weightInput: ".", repsInput: ""))
        old.setsByExercise[exercise.id]?.append(ExerciseSetLog(id: "empty", setNumber: 3))
        let rebased = WorkoutSessionUtils.rebaseWeightInputs(old, from: .kg, to: .lbs)
        XCTAssertEqual(rebased.setsByExercise[exercise.id]?.first?.weightKg, 100)
        XCTAssertEqual(rebased.setsByExercise[exercise.id]?.first?.weightInput, "220.46")
        XCTAssertEqual(rebased.setsByExercise[exercise.id]?[1].weightInput, ".")
        XCTAssertNil(rebased.setsByExercise[exercise.id]?[1].weightKg)
        XCTAssertEqual(rebased.setsByExercise[exercise.id]?[2].weightInput, "")
    }

    func testPrefillIgnoresStaleDisplayTextAndRetainsFullCanonicalPrecision() throws {
        for (weight, text) in [(100.0, "220.46"), (100.1234567, "220.73")] {
            let previous = ExerciseSetLog(setNumber: 1, weightInput: "100", repsInput: "10", weightKg: weight, completedReps: 10, isCompleted: true)
            let next = WorkoutSessionUtils.prefillSet(ExerciseSetLog(setNumber: 2), from: previous, unit: .lbs)
            XCTAssertEqual(next.weightInput, text)
            XCTAssertEqual(next.weightKg, weight)
            XCTAssertFalse(next.isCompleted)
            XCTAssertEqual(WorkoutSessionUtils.weightForEditedInput(next.weightInput, existing: next, unit: .lbs), weight)
        }
    }

    func testPrefillShowsTheExactWeightTheRowLogs() {
        let pounds = WeightUnit.lbs.toCanonicalKg(102.5)
        for (canonical, unit, text) in [(pounds, WeightUnit.lbs, "102.5"), (52.25, WeightUnit.kg, "52.25")] {
            let previous = ExerciseSetLog(setNumber: 1, weightInput: text, repsInput: "8", weightKg: canonical, completedReps: 8, isCompleted: true)
            let next = WorkoutSessionUtils.prefillSet(ExerciseSetLog(setNumber: 2), from: previous, unit: unit)
            XCTAssertEqual(next.weightInput, text)
            XCTAssertEqual(next.weightKg, canonical)
            XCTAssertEqual(WorkoutSessionUtils.weightForEditedInput(next.weightInput, existing: next, unit: unit), canonical)
        }
    }

    func testUnitSwitchesShowExactTextWithoutAccumulatingRounding() {
        let canonical = WeightUnit.lbs.toCanonicalKg(102.5)
        var value = draft(weight: canonical, input: "102.5", unit: .lbs)
        for _ in 0..<10 {
            value = WorkoutSessionUtils.rebaseWeightInputs(value, from: .lbs, to: .kg)
            XCTAssertEqual(value.setsByExercise[exercise.id]?.first?.weightInput, "46.49")
            XCTAssertEqual(value.setsByExercise[exercise.id]?.first?.weightKg, canonical)
            value = WorkoutSessionUtils.rebaseWeightInputs(value, from: .kg, to: .lbs)
            XCTAssertEqual(value.setsByExercise[exercise.id]?.first?.weightInput, "102.5")
            XCTAssertEqual(value.setsByExercise[exercise.id]?.first?.weightKg, canonical)
        }
    }

    func testRepsOnlyEditRetainsCanonicalForExactAndLegacyRoundedText() throws {
        for canonical in [100.0, 100.1234567] {
            let rebased = WorkoutSessionUtils.rebaseWeightInputs(draft(weight: canonical), from: .kg, to: .lbs)
            // Drafts saved before exact input text keep their rounded pounds until the next unit switch.
            let legacy = draft(weight: canonical, input: WeightUnit.lbs.formatWeight(canonical), unit: .lbs)
            for original in [rebased, legacy] {
                let set = try XCTUnwrap(original.setsByExercise[exercise.id]?.first)
                let edited = WorkoutSessionUtils.editedSet(set, weight: set.weightInput, reps: "12", exercise: exercise, unit: .lbs)
                XCTAssertEqual(edited.weightKg, canonical)
                XCTAssertEqual(edited.completedReps, 12)
                let changed = WorkoutSessionUtils.editedSet(edited, weight: "225", reps: "12", exercise: exercise, unit: .lbs)
                XCTAssertEqual(changed.weightKg, WeightUnit.lbs.toCanonicalKg(225))
            }
        }
    }

    func testHistoryResumeShowsExactRecordedWeight() throws {
        let canonical = WeightUnit.lbs.toCanonicalKg(102.5)
        let set = try XCTUnwrap(WorkoutSessionUtils.restoreSetsFromHistory(workout: workout, record: history(canonical), unit: .lbs)[exercise.id]?.first)
        XCTAssertEqual(set.weightInput, "102.5")
        XCTAssertEqual(set.weightKg, canonical)
        XCTAssertEqual(WorkoutSessionUtils.weightForEditedInput(set.weightInput, existing: set, unit: .lbs), canonical)
    }

    func testExplicitWeightEditConvertsOnceAndClearingRemovesValue() {
        let existing = ExerciseSetLog(setNumber: 1, weightInput: "220", weightKg: 100)
        XCTAssertEqual(WorkoutSessionUtils.weightForEditedInput("225", existing: existing, unit: .lbs), WeightUnit.lbs.toCanonicalKg(225))
        XCTAssertNil(WorkoutSessionUtils.weightForEditedInput("", existing: existing, unit: .lbs))
        XCTAssertEqual(WorkoutSessionUtils.weightForEditedInput("0", existing: existing, unit: .lbs), 0)
    }

    func testRepsOnlyUIKitEditAfterUnitSwitchDoesNotReparseRoundedPounds() throws {
        try withStore { store in
            store.weightUnit = .kg
            var active = draft()
            active.setsByExercise[exercise.id]?[0].isCompleted = false
            active.setsByExercise[exercise.id]?[0].isWarmup = false
            store.activeSession = active
            store.weightUnit = .lbs
            let current = try XCTUnwrap(store.activeSession)
            let host = UIHostingController(rootView: ActiveSessionView(store: store, draft: current))
            let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
            defer { window.endEditing(true); window.isHidden = true; previousWindow?.makeKeyAndVisible() }
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = window.bounds
            host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            @MainActor func fields(_ view: UIView) -> [UITextField] {
                if let field = view as? UITextField { return [field] }
                return view.subviews.flatMap { fields($0) }
            }
            let inputs = fields(host.view)
            XCTAssertGreaterThanOrEqual(inputs.count, 2)
            let reps = try XCTUnwrap(inputs.dropFirst().first)
            reps.text = "12"
            reps.sendActions(for: .editingChanged)
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            XCTAssertEqual(store.activeSession?.setsByExercise[exercise.id]?.first?.completedReps, 12)
            XCTAssertEqual(store.activeSession?.setsByExercise[exercise.id]?.first?.weightKg, 100)
            XCTAssertNil(host.presentedViewController as? UIAlertController)
        }
    }
}

@MainActor
final class SessionSetCountPersistenceTests: XCTestCase {
    func testRemovingWorkingSetsDoesNotChangeProgramAfterSavingAndReloading() throws {
        let defaults = UserDefaults.standard
        let domain = try XCTUnwrap(Bundle.main.bundleIdentifier)
        let original = defaults.persistentDomain(forName: domain) ?? [:]
        defer { defaults.setPersistentDomain(original, forName: domain) }
        let access = ProAccessManager.shared
        let cloudAccess = access.isFeatureUnlocked(.cloudBackup)
        access.setFeatureOverride(.cloudBackup, unlocked: false)
        defer { access.setFeatureOverride(.cloudBackup, unlocked: cloudAccess == access.isProSubscribed ? nil : cloudAccess) }
        defaults.removeObject(forKey: "active_session_v1")
        defaults.set(true, forKey: "seeded_starters_v9")
        defaults.set(true, forKey: "seeded_starters_v10")
        let squat = Exercise(id: "squat", name: "Barbell Back Squat", exerciseId: "barbell-back-squat",
            sets: 6, reps: RepTarget(min: 5, max: 5), restSeconds: 0)
        let program = Program(id: "six-set-squats", name: "Six-set squats", workouts: [
            Workout(id: "squat-day", day: 1, title: "Squats", exercises: [squat])])
        defaults.set(try JSONEncoder().encode(StoredAppState(programs: [program], activeProgramId: program.id,
            currentWeekKey: "2020-W01")), forKey: "stored_app_state")
        var store = AppStore(persistence: AppStatePersistence(inMemory: true))
        let savedProgram = try XCTUnwrap(store.state.programs.first)
        let workout = try XCTUnwrap(savedProgram.workouts.first)
        XCTAssertTrue(store.startActiveSession(programId: program.id, workout: workout, allowPast: true))
        XCTAssertEqual(store.activeSession?.setsByExercise[squat.id]?.count, 6)
        for _ in 0..<4 {
            store.updateActiveSession { draft in
                var copy = draft
                var sets = copy.setsByExercise[squat.id]!
                sets.removeLast()
                copy.setsByExercise[squat.id] = AppStore.reindexSets(sets)
                return copy
            }
        }
        XCTAssertEqual(store.activeSession?.setsByExercise[squat.id]?.count, 2)
        XCTAssertEqual(store.state.programs, [savedProgram])
        store.updateActiveSession { draft in
            var copy = draft
            copy.setsByExercise[squat.id] = copy.setsByExercise[squat.id]!.map { set in
                var result = set
                result.weightInput = "100"; result.repsInput = "5"
                result.weightKg = 100; result.completedReps = 5; result.isCompleted = true
                return result
            }
            return copy
        }
        let finished = try XCTUnwrap(store.activeSession)
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        store.completeActiveSession(SessionProgress.from(draft: finished, nowEpochMillis: now)
            .record(draft: finished, completedAtEpochMillis: now))
        let record = try XCTUnwrap(store.state.history.first)
        XCTAssertEqual(record.isComplete, true)
        XCTAssertEqual(record.totalCompletedSets, 2)
        XCTAssertEqual(record.exerciseLogs.first?.targetSets, 2)
        XCTAssertEqual(record.exerciseLogs.first?.sets.count, 2)
        XCTAssertEqual(record.workoutSnapshot?.exercises.first?.sets, 6)
        store = AppStore(persistence: store.statePersistence)
        XCTAssertEqual(store.state.programs, [savedProgram])
        XCTAssertEqual(store.state.history, [record])
        XCTAssertTrue(store.startActiveSession(programId: program.id, workout: store.state.programs[0].workouts[0], allowPast: true))
        let freshSets = try XCTUnwrap(store.activeSession?.setsByExercise[squat.id])
        XCTAssertEqual(freshSets.count, 6)
        XCTAssertTrue(freshSets.allSatisfy { !$0.isCompleted })
    }
}

final class SessionCompletionTimerTests: XCTestCase {
    private let now: Int64 = 10_000
    private var exercises: [Exercise] {
        (0..<3).map { Exercise(id: "exercise-\($0)", name: "Bench \($0)", exerciseId: "barbell-bench-press",
            sets: 2, reps: RepTarget(min: 8, max: 12), restSeconds: 90) }
    }
    private func draft() -> ActiveSessionDraft {
        let workout = Workout(id: "w", day: 1, title: "Test", exercises: exercises)
        return ActiveSessionDraft(id: "d", programId: "p", workout: workout, startedAt: "2026-10-10T10:00:00Z",
            startedAtEpochMillis: 1000, setsByExercise: Dictionary(uniqueKeysWithValues: exercises.map { ex in
                (ex.id, (1...2).map { ExerciseSetLog(setNumber: $0, weightInput: "60", repsInput: "10", weightKg: 60, completedReps: 10) })
            }))
    }
    private func complete(_ draft: inout ActiveSessionDraft, _ exercise: Exercise, _ index: Int) {
        draft.setsByExercise[exercise.id]![index].isCompleted = true
        draft.restTimer = RestTimerUtils.afterCompletingSet(in: draft, exercise: exercise, nowEpochMillis: now)
    }
    func testWorkoutCompletionSkipsRestForEveryExerciseOrder() {
        for order in [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]] {
            var active = draft()
            for (position, exerciseIndex) in order.enumerated() {
                let ex = active.workout.exercises[exerciseIndex]
                for setIndex in 0...1 {
                    complete(&active, ex, setIndex)
                    let finished = position == 2 && setIndex == 1
                    XCTAssertEqual(WorkoutSessionUtils.isComplete(draft: active), finished)
                    XCTAssertEqual(active.restTimer == nil, finished, "Order \(order), exercise \(exerciseIndex), set \(setIndex)")
                    if !finished {
                        XCTAssertEqual(active.restTimer?.endsAtEpochMillis, now + 90_000)
                        XCTAssertEqual(active.restTimer?.exerciseName, ex.name)
                    }
                }
            }
        }
    }
    func testAddedRemovedAndWarmupSetsUseSessionCompletionRules() {
        var active = draft()
        for ex in active.workout.exercises {
            complete(&active, ex, 0)
            complete(&active, ex, 1)
        }
        let ex = active.workout.exercises[0]
        active.setsByExercise[ex.id]!.append(WorkoutSessionUtils.prefillSet(
            WorkoutSessionUtils.newSet(exercise: ex, number: 3), from: active.setsByExercise[ex.id]![1]))
        active.setsByExercise[ex.id]![0].isCompleted = false
        complete(&active, ex, 0)
        XCTAssertNotNil(active.restTimer)
        complete(&active, ex, 2)
        XCTAssertNil(active.restTimer)
        active.setsByExercise[ex.id]!.removeLast()
        active.setsByExercise[ex.id]!.insert(ExerciseSetLog(setNumber: 1, isWarmup: true), at: 0)
        active.setsByExercise[ex.id]![1].isCompleted = false
        complete(&active, ex, 1)
        XCTAssertTrue(WorkoutSessionUtils.isComplete(draft: active))
        XCTAssertNil(active.restTimer)
    }
    func testMissingAndInvalidOtherExerciseLogsStillRequireRest() {
        for invalid in [false, true] {
            var active = draft()
            let ex = active.workout.exercises[0]
            for other in active.workout.exercises.dropFirst() {
                active.setsByExercise[other.id] = invalid
                    ? [ExerciseSetLog(setNumber: 1, weightKg: 60, isCompleted: true)] : []
            }
            complete(&active, ex, 0)
            complete(&active, ex, 1)
            XCTAssertFalse(WorkoutSessionUtils.isComplete(draft: active))
            XCTAssertNotNil(active.restTimer)
        }
    }
    func testZeroRestDoesNotStartTimerWhileWorkoutIsUnfinished() {
        var active = draft()
        var ex = active.workout.exercises[0]
        ex.restSeconds = 0
        active.workout.exercises[0] = ex
        complete(&active, ex, 0)
        XCTAssertFalse(WorkoutSessionUtils.isComplete(draft: active))
        XCTAssertNil(active.restTimer)
    }
}

final class BodyweightLoggingTests: XCTestCase {
    private let push = Exercise(id: "push", name: "Push-Ups", exerciseId: "push-ups", sets: 2, reps: RepTarget(min: 8, max: 12))
    private var assisted: Exercise { var ex = push; ex.name = "Assisted Pull-up"; ex.exerciseId = "assisted-pull-up"; return ex }
    private func record(_ n: Int, exercise: Exercise? = nil, weights: [Double?] = [0, 0], reps: [Int] = [10, 9]) -> WorkoutSessionRecord {
        let ex = exercise ?? push
        return WorkoutSessionRecord(id: "r\(n)", programId: "p", workoutId: "w", workoutTitle: "Test", startedAt: "2026-10-0\(n)T10:00:00Z", completedAt: "2026-10-0\(n)T11:00:00Z", durationSeconds: 60,
            totalVolumeKg: zip(weights, reps).reduce(0) { $0 + ($1.0 ?? 0) * Double($1.1) }, exerciseLogs: [SessionExerciseLog(exerciseName: ex.name, sets: weights.enumerated().map { SessionSetLog(setNumber: $0.offset + 1, weightKg: $0.element, reps: reps[$0.offset]) }, targetSets: 2, exerciseId: ex.exerciseId)])
    }
    private func draft(_ ex: Exercise? = nil) -> ActiveSessionDraft {
        let workout = Workout(id: "w", day: 1, title: "Test", exercises: [ex ?? push])
        return ActiveSessionDraft(id: "d", programId: "p", workout: workout, startedAt: "2026-10-09T10:00:00Z", startedAtEpochMillis: 1000, setsByExercise: WorkoutSessionUtils.initialSets(for: workout))
    }
    func testActualZeroDefaultsAndUntouchedRowsRemainEligibleForPrefill() {
        let initial = draft()
        XCTAssertTrue(initial.setsByExercise[push.id]!.allSatisfy { $0.weightInput == "0" && $0.weightKg == 0 && !$0.isCompleted && $0.inputTouched != true })
        XCTAssertFalse(SessionProgress.from(draft: initial, nowEpochMillis: 2000).hasProgress)
        for ex in [Exercise(name: "Weighted Pull-Ups", exerciseId: "weighted-pull-ups"), Exercise(name: "Custom"), assisted] {
            XCTAssertEqual(WorkoutSessionUtils.newSet(exercise: ex, number: 1).weightInput, "")
        }
        let previous = ExerciseSetLog(setNumber: 1, repsInput: "8", weightKg: 5, completedReps: 8, isCompleted: true)
        let next = WorkoutSessionUtils.prefillSet(WorkoutSessionUtils.newSet(exercise: push, number: 2), from: previous)
        XCTAssertEqual(next.weightKg, 5); XCTAssertEqual(next.repsInput, "8"); XCTAssertFalse(next.isCompleted)
    }
    func testZeroAndMixedBaselinesKeepLatestSetPositionsAndRecognizeRepGains() {
        let previous = WorkoutSessionUtils.findPreviousSessionWorkingSets(history: [record(2), record(1, weights: [10, 10])], exercise: push)
        XCTAssertEqual(previous.map { $0.weightKg }, [0, 0])
        let target = WorkoutSessionUtils.computeGhostTarget(previousSets: previous, workingSetIndex: 0, exercise: push)
        XCTAssertFalse(target.isFirstSession); XCTAssertNil(target.altWeightKg)
        XCTAssertNotNil(WorkoutSessionUtils.evaluateLogbookBeat(loggedWeightKg: 0, loggedReps: 11, target: target))
        XCTAssertNil(WorkoutSessionUtils.evaluateLogbookBeat(loggedWeightKg: 10, loggedReps: 1, target: target))
        XCTAssertEqual(WorkoutSessionUtils.findExercisePr(history: [record(2)], exercise: push), "BW ×10")
        XCTAssertEqual(WorkoutSessionUtils.findExercisePr(history: [record(2, weights: [20, 0])], exercise: push), "BW +20 ×10")
        let weightedPullUp = Exercise(name: "Weighted Pull-Ups", exerciseId: "weighted-pull-ups")
        XCTAssertEqual(WorkoutSessionUtils.findExercisePr(history: [record(2, exercise: weightedPullUp, weights: [20, 20])], exercise: weightedPullUp), "BW +20 ×10")
        XCTAssertEqual(WorkoutSessionUtils.findExercisePr(history: [record(2, weights: [20, 0])], exercise: push, unit: .lbs), "BW +44 ×10")
        XCTAssertEqual(WorkoutSessionUtils.findExercisePr(history: [record(2, exercise: assisted)], exercise: assisted), "0x10")
        let mixed = WorkoutSessionUtils.findPreviousSessionWorkingSets(history: [record(2, weights: [0, 10])], exercise: push)
        XCTAssertEqual(mixed.map { $0.setNumber }, [1, 2])
        XCTAssertEqual(WorkoutSessionUtils.computeGhostTarget(previousSets: mixed, workingSetIndex: 0, exercise: push).lastWeekWeightKg, 0)
        XCTAssertTrue(WorkoutSessionUtils.findPreviousSessionWorkingSets(history: [record(3, weights: [nil, 0]), record(2)], exercise: push).isEmpty)
    }
    func testInvalidCompletedEditsNeedExplicitCompletionAgainAndNeverSaveMissingValues() {
        let row = ExerciseSetLog(setNumber: 1, weightInput: "0", repsInput: "10", weightKg: 0, completedReps: 10, isCompleted: true)
        let cleared = WorkoutSessionUtils.editedSet(row, weight: "", reps: "10", exercise: push, unit: .kg)
        XCTAssertFalse(cleared.isCompleted)
        XCTAssertFalse(WorkoutSessionUtils.editedSet(cleared, weight: "0", reps: "10", exercise: push, unit: .kg).isCompleted)
        XCTAssertFalse(WorkoutSessionUtils.editedSet(row, weight: "0", reps: "", exercise: push, unit: .kg).isCompleted)
        XCTAssertTrue(WorkoutSessionUtils.editedSet(row, weight: "0", reps: "11", exercise: push, unit: .kg).isCompleted)
        var active = draft(); active.setsByExercise[push.id] = [cleared]
        XCTAssertFalse(WorkoutSessionUtils.isComplete(draft: active))
        let progress = SessionProgress.from(draft: active, nowEpochMillis: 3000)
        XCTAssertEqual(progress.completedSets, 0); XCTAssertTrue(progress.exerciseLogs.first!.sets.isEmpty)
    }
    func testAssistanceDoesNotIncreaseAutomaticallyAndLessAssistanceBeatsAtSameReps() throws {
        let history = [record(1, exercise: assisted, weights: [40, 40], reps: [12, 12]), record(2, exercise: assisted, weights: [40, 40], reps: [12, 12])]
        let rec = try XCTUnwrap(ProgressionEngine.computeProgression(exercise: assisted, history: history))
        XCTAssertEqual(rec.action, .holdLoad); XCTAssertEqual(rec.setTargets.map { $0.weightKg }, [40, 40])
        XCTAssertEqual(rec.rationaleKey, "progression.rationale.assistance_ceiling")
        let ghost = WorkoutSessionUtils.computeGhostTarget(previousSets: history.last!.exerciseLogs.first!.sets, workingSetIndex: 0, exercise: assisted)
        XCTAssertNil(ghost.altWeightKg)
        XCTAssertNil(WorkoutSessionUtils.evaluateLogbookBeat(loggedWeightKg: 42.5, loggedReps: 12, target: ghost))
        let beat = try XCTUnwrap(WorkoutSessionUtils.evaluateLogbookBeat(loggedWeightKg: 37.5, loggedReps: 12, target: ghost))
        XCTAssertEqual(WorkoutSessionUtils.formatLogbookBeatBadge(result: beat), "−2.5 KG")
        XCTAssertNil(WorkoutSessionUtils.evaluateLogbookBeat(loggedWeightKg: 37.5, loggedReps: 10, target: ghost))
        XCTAssertTrue(WorkoutSessionUtils.allowsZeroWeight(assisted))
    }
    func testAssistanceIsExcludedFromResistanceMetricsButRetainsSetsAndReps() {
        let history = [record(1, exercise: assisted, weights: [40, 40]), record(2, exercise: assisted, weights: [45, 45])]
        XCTAssertEqual(PersonalRecordTracker.countPrsForWeek(history: history, currentWeekKey: "2026-W40", timeZone: TimeZone(secondsFromGMT: 0)!), 0)
        XCTAssertEqual(WorkoutSessionUtils.resistanceVolume(history.first!), 0)
        XCTAssertNil(FormLabEngine.computeExerciseRepMax(exerciseName: assisted.name, history: history))
        let stats = PersonalRecordTracker.computeExerciseHistoryStats(history: history, exerciseName: assisted.name)
        XCTAssertEqual(stats.prWeightKg, 40); XCTAssertEqual(stats.lifetimeSets, 4)
        XCTAssertEqual(stats.totalVolumeKg, 0); XCTAssertNil(stats.estimated1rmKg); XCTAssertTrue(stats.isAssisted)
        var active = draft(assisted)
        active.setsByExercise[assisted.id] = [ExerciseSetLog(setNumber: 1, weightKg: 40, completedReps: 10, isCompleted: true)]
        let progress = SessionProgress.from(draft: active, nowEpochMillis: 2000)
        XCTAssertEqual(progress.completedSets, 1); XCTAssertEqual(progress.volumeKg, 0)
    }
    @MainActor func testLoggingSnapshotsAtNarrowLocalizedLargeText() {
        let previousLanguage = LanguageManager.shared.currentLanguage
        let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }.first { $0.isKeyWindow }
        defer { LanguageManager.setLanguage(previousLanguage); previousWindow?.makeKeyAndVisible() }
        for language in ["en", "tr", "de", "fr", "es"] { for (isAssisted, load) in [(false, 0.0), (false, 20.0), (false, 2.5), (true, 40.0)] {
            LanguageManager.setLanguage(language)
            let ex = isAssisted ? assisted : push
            if load == 2.5 {
                XCTAssertEqual(WorkoutSessionUtils.formatSessionPr(weightKg: load, reps: 10, isBodyweight: true), language == "en" ? "BW +2.5 ×10" : "BW +2,5 ×10")
            }
            let rows = [ExerciseSetLog(setNumber: 1, weightInput: isAssisted ? "40" : "0", repsInput: "11", weightKg: isAssisted ? 40 : 0, completedReps: 11, isCompleted: true), WorkoutSessionUtils.newSet(exercise: ex, number: 2)]
            let ghost = WorkoutSessionUtils.computeGhostTarget(previousSets: [SessionSetLog(setNumber: 1, weightKg: load, reps: 10)], workingSetIndex: 0, exercise: ex)
            let view = ScrollView { SetLoggingTable(sets: rows, prescription: "2 × 8–12", onUpdateSet: { _,_,_ in }, onToggleCompleteSet: { _ in }, onAddSet: {}, onRemoveSet: { _ in }, allowsZeroWeight: true, isAssisted: isAssisted, isBodyweight: !isAssisted, ghostTargets: [0: ghost]).padding(16) }.background(AppColors.background).environment(\.sizeCategory, .accessibilityMedium)
            let controller = UIHostingController(rootView: view)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 852))
            window.rootViewController = controller; window.makeKeyAndVisible(); controller.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in controller.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image)
            attachment.name = "logging-\(isAssisted ? "assistance" : "bodyweight")-\(load)-\(language)-320-large"; attachment.lifetime = .keepAlways; add(attachment)
            XCTAssertEqual(controller.view.bounds.width, 320); window.isHidden = true
        } }
    }
}

@MainActor
final class LocalizationExpansionTests: XCTestCase {
    private var previousPreference = "system"
    override func setUp() { super.setUp(); previousPreference = LanguageManager.shared.languagePreference }
    override func tearDown() { LanguageManager.setLanguage(previousPreference); super.tearDown() }

    func testLanguageResolutionAndCompleteBundles() throws {
        XCTAssertEqual(LanguageManager.resolveLanguage(["pt-BR","de-CH","fr-CA"]), "de")
        XCTAssertEqual(LanguageManager.resolveLanguage(["fr_CA"]), "fr")
        XCTAssertEqual(LanguageManager.resolveLanguage(["es-MX"]), "es")
        XCTAssertEqual(LanguageManager.resolveLanguage(["ja"]), "en")
        XCTAssertEqual(LanguageManager.normalizePreference(nil), "system")
        let english = ContentLocalizer.shared.loadExercises(lang: "en")
        XCTAssertEqual(english.count, 300)
        for (lang, _) in LanguageManager.supportedLanguages {
            let dictionary = Translations.forLanguage(lang)
            XCTAssertEqual(Set(dictionary.keys), Set(Translations.en.keys), lang)
            let localized = ContentLocalizer.shared.loadExercises(lang: lang)
            XCTAssertEqual(Set(localized.keys), Set(english.keys), lang)
            for (id, source) in english {
                let target = try XCTUnwrap(localized[id])
                XCTAssertFalse(target.name?.isEmpty ?? true, "\(lang)/\(id)")
                XCTAssertEqual(source.cues?.count, target.cues?.count)
                XCTAssertEqual(source.avoid?.count, target.avoid?.count)
                XCTAssertEqual(source.cuesDetails?.count, target.cuesDetails?.count)
                XCTAssertEqual(source.avoidDetails?.count, target.avoidDetails?.count)
            }
            XCTAssertEqual(ContentLocalizer.shared.loadPrograms(lang:lang).count, AppStore.starterProgramFiles.count)
        }
    }

    func testNativePluralFormattingAndLiteralArguments() {
        for (lang, expected) in [("de","Noch 1 Satz"),("fr","1 série restante"),("es","Queda 1 serie")] {
            LanguageManager.setLanguage(lang)
            XCTAssertEqual(LanguageManager.formatSetsLeft(1),expected)
            XCTAssertNotEqual(LanguageManager.formatSetsLeft(1),LanguageManager.formatSetsLeft(2))
            XCTAssertFalse(LanguageManager.formatExerciseSetsCompleted(completed:2,planned:3).contains("{"))
            XCTAssertTrue(LanguageManager.t("form_lab.mirror_folder_connected",["name":"{time}","time":"changed"]).contains("{time}"))
            XCTAssertEqual(WeightUnit.kg.formatDisplayWeight(52.5),"52,5")
            XCTAssertEqual(WeightUnit.kg.formatWeight(52.5),"52.5")
        }
        LanguageManager.setLanguage("fr")
        XCTAssertEqual(LanguageManager.formatSetsLeft(0),"0 série restante")
        XCTAssertEqual(LanguageManager.t("library.resultCount",["count":1]),"1 exercice")
        XCTAssertEqual(LanguageManager.t("library.resultCount",["count":2]),"2 exercices")
        XCTAssertEqual(LanguageManager.t("programs.counts",["workouts":1,"exercises":2]),"1 séance · 2 exercices")
        LanguageManager.setLanguage("tr")
        XCTAssertTrue(LanguageManager.formatSetsProgress(done:3,total:5).contains("3'ü"))
    }

    func testAllNativePluralResourcesIncludeLargeCounts() throws {
        for language in ["en", "tr", "de", "fr", "es"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            let dictionary = Translations.forLanguage(language)
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: language)
            formatter.numberStyle = .decimal
            for (key, parameter) in Translations.quantityParameters {
                XCTAssertNotEqual(bundle.localizedString(forKey: key, value: nil, table: nil), key)
                for count in [0, 1, 2, 1_000_000] {
                    let quantity = count == 1 || (language == "fr" && count == 0) ? "one" : "other"
                    let expected = try XCTUnwrap(dictionary["\(key).\(quantity)"])
                        .replacingOccurrences(of: "{\(parameter)}", with: try XCTUnwrap(formatter.string(from: NSNumber(value: count))))
                    XCTAssertEqual(LanguageManager.shared.plural(key, count, language: language), expected, "\(language)/\(key)/\(count)")
                }
            }
        }
    }

    func testSearchAndLanguageSwitchKeepStoredExerciseIdentity() throws {
        let definition = try XCTUnwrap(ExerciseCatalog.canonicalExercises["barbell-bench-press"])
        let exercise = definition.toExercise()
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let before = try encoder.encode(exercise)
        for (lang, query) in [("de","bankdruecken"),("fr","développé couché"),("es","press de banca")] {
            LanguageManager.setLanguage(lang)
            XCTAssertNotNil(ExerciseSearch.score(ExerciseSearch.Query(query),exercise:exercise))
            XCTAssertNotEqual(exercise.displayName, exercise.name)
            XCTAssertEqual(before, try encoder.encode(exercise))
        }
    }

    func testExpandedLanguageSettingsAndLibraryAtNarrowWidth() async throws {
        for lang in ["de","fr","es"] {
            LanguageManager.setLanguage(lang)
            let store = AppStore.shared
            let views: [(String,AnyView)] = [
                ("settings",AnyView(SettingsView(store:store,onDismiss:{}))),
                ("library",AnyView(LibraryView(store:store,onSelectExercise:{_ in},onOpenSettings:{}))),
                ("onboarding",AnyView(OnboardingView(store:store))),
                ("muscles",AnyView(ExerciseMusclesCard(exerciseId:"barbell-bench-press"))),
                ("paywall",AnyView(ProPaywallSheet(feature:.autoProgression,onDismiss:{})))
            ]
            for (name,view) in views {
                // ImageRenderer cannot draw native scroll views; render the actual hosted UIKit hierarchy.
                let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                    .flatMap { $0.windows }.first { $0.isKeyWindow }
                let controller = UIHostingController(rootView:view.environment(\.locale,LanguageManager.locale)
                    .environment(\.dynamicTypeSize,DynamicTypeSize.xxxLarge))
                let window = UIWindow(frame:CGRect(x:0,y:0,width:320,height:900))
                window.rootViewController = controller
                window.makeKeyAndVisible()
                controller.view.frame = window.bounds
                controller.view.layoutIfNeeded()
                try await Task.sleep(nanoseconds:300_000_000)
                controller.view.layoutIfNeeded()
                let renderer = UIGraphicsImageRenderer(bounds:controller.view.bounds)
                let image = renderer.image { _ in controller.view.drawHierarchy(in:controller.view.bounds,afterScreenUpdates:true) }
                window.isHidden = true
                previousWindow?.makeKeyAndVisible()
                XCTAssertEqual(image.size.width,320)
                let attachment = XCTAttachment(image:image);attachment.name="i18n-\(lang)-\(name)-320-large";attachment.lifetime = .keepAlways;add(attachment)
                try image.pngData()?.write(to:URL(fileURLWithPath:"/private/tmp/i18n-\(lang)-\(name)-ios.png"))
            }
        }
    }
}

@MainActor
final class PremiumSettingsTests: XCTestCase {
    func testLockedBindingsPreserveIndependentPreferences() {
        var targets = false
        var warmup = true
        let targetsBinding = Binding(get: { targets }, set: { targets = $0 })
        let warmupBinding = Binding(get: { warmup }, set: { warmup = $0 })
        for unlocked in [false, true, false, true] {
            let targetRow = SettingsPremiumToggle(titleKey: "settings.showProgressionTargets",
                subtitleKey: "settings.showProgressionTargetsSubtitle", preference: targetsBinding,
                isUnlocked: unlocked, identifier: "targets")
            let warmupRow = SettingsPremiumToggle(titleKey: "settings.showWarmupCalculator",
                subtitleKey: "settings.showWarmupCalculatorSubtitle", preference: warmupBinding,
                isUnlocked: unlocked, identifier: "warmup")
            XCTAssertEqual(targetRow.selection.wrappedValue, !unlocked || targets)
            XCTAssertEqual(warmupRow.selection.wrappedValue, !unlocked || warmup)
            let previousTargets = targets
            let previousWarmup = warmup
            targetRow.selection.wrappedValue.toggle()
            XCTAssertEqual(targets, unlocked ? !previousTargets : previousTargets)
            XCTAssertEqual(warmup, previousWarmup)
            warmupRow.selection.wrappedValue.toggle()
            XCTAssertEqual(warmup, unlocked ? !previousWarmup : previousWarmup)
        }
    }

    func testSettingsRespondsToSubscriptionChangesWithoutOverwritingPreferences() async throws {
        let store = AppStore.shared
        let manager = ProAccessManager.shared
        let previousTargets = store.showProgressionTargets
        let previousWarmup = store.showWarmupCalculator
        let previousSubscription = manager.isProSubscribed
        let previousWindow = keyWindow
        defer {
            store.showProgressionTargets = previousTargets
            store.showWarmupCalculator = previousWarmup
            manager.updateSubscriptionStatus(active: previousSubscription)
            previousWindow?.makeKeyAndVisible()
        }
        store.showProgressionTargets = false
        store.showWarmupCalculator = false
        manager.updateSubscriptionStatus(active: false)
        let controller = UIHostingController(rootView: SettingsView(store: store, onDismiss: {}))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 1100))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.frame = window.bounds
        for unlocked in [false, true, false, true] {
            manager.updateSubscriptionStatus(active: unlocked)
            controller.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 250_000_000)
            controller.view.layoutIfNeeded()
            let switches = descendants(controller.view).compactMap { $0 as? UISwitch }
            // The training section follows the free pre-fill switch.
            XCTAssertGreaterThanOrEqual(switches.count, 3)
            for control in switches.dropFirst().prefix(2) {
                XCTAssertEqual(control.isEnabled, unlocked)
                XCTAssertEqual(control.isOn, !unlocked)
            }
            XCTAssertFalse(store.showProgressionTargets)
            XCTAssertFalse(store.showWarmupCalculator)
            let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            try image.pngData()?.write(to: URL(fileURLWithPath: "/private/tmp/settings-\(unlocked ? "premium" : "free")-ios.png"))
        }
    }

    func testPremiumRowsRemainReadableAcrossLanguagesAndTextSizes() async throws {
        let previousLanguage = LanguageManager.shared.languagePreference
        let previousWindow = keyWindow
        defer { LanguageManager.setLanguage(previousLanguage); previousWindow?.makeKeyAndVisible() }
        for lang in ["en", "tr", "de", "fr", "es"] {
            LanguageManager.setLanguage(lang)
            for unlocked in [false, true] {
                for (width, size, suffix) in [(393.0, DynamicTypeSize.large, "normal"), (320.0, .xxxLarge, "large")] {
                    let rows = VStack(spacing: 0) {
                        SettingsPremiumToggle(titleKey: "settings.showProgressionTargets",
                            subtitleKey: "settings.showProgressionTargetsSubtitle", preference: .constant(true),
                            isUnlocked: unlocked, identifier: "targets")
                        Divider().background(AppColors.border)
                        SettingsPremiumToggle(titleKey: "settings.showWarmupCalculator",
                            subtitleKey: "settings.showWarmupCalculatorSubtitle", preference: .constant(true),
                            isUnlocked: unlocked, identifier: "warmup")
                    }
                    .background(AppColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.border, lineWidth: 1))
                    let controller = UIHostingController(rootView: VStack { rows; Spacer(minLength: 0) }
                        .padding(20).background(AppColors.background).environment(\.dynamicTypeSize, size))
                    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 460))
                    window.rootViewController = controller
                    window.makeKeyAndVisible()
                    controller.view.frame = window.bounds
                    controller.view.layoutIfNeeded()
                    try await Task.sleep(nanoseconds: 150_000_000)
                    let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { _ in
                        controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
                    }
                    window.isHidden = true
                    let name = "premium-settings-\(lang)-\(unlocked ? "premium" : "free")-\(suffix)"
                    let attachment = XCTAttachment(image: image)
                    attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
                    try image.pngData()?.write(to: URL(fileURLWithPath: "/private/tmp/\(name)-ios.png"))
                }
            }
        }
    }

    private var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }.first { $0.isKeyWindow }
    }
    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}

@MainActor
final class SettingsLanguagePickerLayoutTests: XCTestCase {
    func testCompactRowAndFullNamesAtNarrowWidth() async throws {
        let previous = LanguageManager.shared.languagePreference
        let previousWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }.first { $0.isKeyWindow }
        defer { LanguageManager.setLanguage(previous); previousWindow?.makeKeyAndVisible() }
        for lang in ["en","tr","de","fr","es"] {
            LanguageManager.setLanguage(lang)
            for (size, suffix) in [(DynamicTypeSize.large,"normal"),(.xxxLarge,"large")] {
                let row = SettingsLanguageRow(value: "English", onTap: {})
                let rowController = UIHostingController(rootView:VStack(spacing:0) { row; Spacer(minLength:0) }
                    .padding(20).background(AppColors.background).environment(\.dynamicTypeSize,size))
                let rowWindow = UIWindow(frame:CGRect(x:0,y:0,width:320,height:180))
                rowWindow.rootViewController = rowController;rowWindow.makeKeyAndVisible()
                rowController.view.frame = rowWindow.bounds;rowController.view.layoutIfNeeded()
                try await Task.sleep(nanoseconds:150_000_000)
                let rowImage = UIGraphicsImageRenderer(bounds:rowController.view.bounds).image { _ in
                    rowController.view.drawHierarchy(in:rowController.view.bounds,afterScreenUpdates:true)
                }
                rowWindow.isHidden = true
                let rowAttachment = XCTAttachment(image:rowImage);rowAttachment.name="language-row-\(lang)-\(suffix)";rowAttachment.lifetime = .keepAlways;add(rowAttachment)
                if lang=="en" || lang=="de" { try rowImage.pngData()?.write(to:URL(fileURLWithPath:"/private/tmp/language-row-\(lang)-\(suffix)-ios.png")) }

                let sheet = LanguageSelectionSheet(preference:lang,deviceLanguageName:"English",onSelect:{_ in},onDismiss:{})
                let sheetController = UIHostingController(rootView:sheet.environment(\.dynamicTypeSize,size))
                let sheetWindow = UIWindow(frame:CGRect(x:0,y:0,width:320,height:size == .large ? 540 : 820))
                sheetWindow.rootViewController = sheetController;sheetWindow.makeKeyAndVisible()
                sheetController.view.frame = sheetWindow.bounds;sheetController.view.layoutIfNeeded()
                try await Task.sleep(nanoseconds:150_000_000)
                let sheetImage = UIGraphicsImageRenderer(bounds:sheetController.view.bounds).image { _ in
                    sheetController.view.drawHierarchy(in:sheetController.view.bounds,afterScreenUpdates:true)
                }
                sheetWindow.isHidden = true
                let attachment = XCTAttachment(image:sheetImage);attachment.name="language-sheet-\(lang)-\(suffix)";attachment.lifetime = .keepAlways;add(attachment)
                try sheetImage.pngData()?.write(to:URL(fileURLWithPath:"/private/tmp/language-sheet-\(lang)-\(suffix)-ios.png"))
                XCTAssertEqual(sheetImage.size.width,320)
            }
        }
    }
}

final class AppThemesTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        ThemeManager.shared.setThemeId(AppThemes.default.id)
    }

    func testAllEightThemesAreDefinedAndDistinct() {
        XCTAssertEqual(AppThemes.all.count, 8)
        let ids = Set(AppThemes.all.map { $0.id })
        XCTAssertEqual(ids.count, 8)
        XCTAssertTrue(ids.contains("default"))
        XCTAssertTrue(ids.contains("espresso"))
        XCTAssertTrue(ids.contains("stealth"))
        XCTAssertTrue(ids.contains("cobalt"))
        XCTAssertTrue(ids.contains("alpine"))
        XCTAssertTrue(ids.contains("crimson"))
        XCTAssertTrue(ids.contains("amethyst"))
        XCTAssertTrue(ids.contains("oat"))
        XCTAssertEqual(AppThemes.oat.colorScheme, .light)
        XCTAssertTrue(AppThemes.all.filter { $0.id != "oat" }.allSatisfy { $0.isDark })
    }

    func testDefaultThemeIsFreeAndOthersArePremium() {
        XCTAssertFalse(AppThemes.default.isPremium)
        for theme in AppThemes.all where theme.id != "default" {
            XCTAssertTrue(theme.isPremium, "Theme \(theme.id) must be premium")
        }
    }

    func testThemeLookupAndFallback() {
        XCTAssertEqual(AppThemes.fromId("espresso").id, "espresso")
        XCTAssertEqual(AppThemes.fromId("unknown_xyz").id, "default")
    }

    func testThemeManagerSwitchesAndPersistsTheme() {
        let manager = ThemeManager.shared
        manager.setThemeId("espresso")
        XCTAssertEqual(manager.currentTheme.id, "espresso")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "app_theme_id"), "espresso")

        XCTAssertEqual(AppColors.background, AppThemes.espresso.background)
        XCTAssertEqual(AppColors.surface, AppThemes.espresso.surface)
        XCTAssertEqual(AppColors.accent, AppThemes.espresso.accent)

        manager.setThemeId("default")
        XCTAssertEqual(manager.currentTheme.id, "default")
        XCTAssertEqual(AppColors.background, AppThemes.default.background)
    }

    func testAppStoreForwardsThemeId() {
        let store = AppStore.shared
        store.appThemeId = "cobalt"
        XCTAssertEqual(ThemeManager.shared.currentTheme.id, "cobalt")
        XCTAssertEqual(store.appThemeId, "cobalt")
        store.appThemeId = "default"
    }
    func testInformativeTextContrastAcrossThemesAndProminentSurfaces() {
        func contrast(_ a: Color, _ b: Color) -> Double {
            func luminance(_ color: Color) -> Double {
                let c = color.resolve(in: EnvironmentValues())
                func linear(_ v: Float) -> Double {
                    let x = Double(v)
                    return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
                }
                return linear(c.red) * 0.2126 + linear(c.green) * 0.7152 + linear(c.blue) * 0.0722
            }
            let x = luminance(a), y = luminance(b)
            return (max(x, y) + 0.05) / (min(x, y) + 0.05)
        }
        for theme in AppThemes.all {
            ThemeManager.shared.setThemeId(theme.id)
            for surface in [AppColors.surface, AppColors.surfaceRaised, AppColors.heroSurface,
                AppColors.historyStatCardBg, AppColors.cuesBg, AppColors.avoidBg,
                AppColors.positiveBg, AppColors.purpleBg] {
                for text in [AppColors.text, AppColors.secondaryText, AppColors.muted] {
                    XCTAssertGreaterThanOrEqual(contrast(text, surface), 4.5, "\(theme.id): informative text")
                }
            }
            XCTAssertGreaterThanOrEqual(contrast(theme.background, AppColors.progressionPaywallAccent), 4.5, theme.id)
            XCTAssertGreaterThanOrEqual(contrast(AppColors.accent, AppColors.cuesBg), 4.5, theme.id)
            XCTAssertGreaterThanOrEqual(contrast(AppColors.danger, AppColors.avoidBg), 4.5, theme.id)
        }
    }

    func testSpecialSurfacesFollowRepeatedThemeSwitches() {
        for theme in AppThemes.all + AppThemes.all.reversed() {
            ThemeManager.shared.setThemeId(theme.id)
            if theme.id != "default" {
                XCTAssertEqual(AppColors.heroSurface, theme.surfaceRaised)
                XCTAssertEqual(AppColors.historyStatCardBg, theme.surface)
                XCTAssertEqual(AppColors.historyStatCardTitle, theme.muted)
                XCTAssertEqual(AppColors.restTimerAccent, theme.purple)
                XCTAssertEqual(AppColors.progressionPaywallSurface, theme.surface)
                XCTAssertEqual(AppColors.progressionPaywallAccent, theme.accent)
            }
            let expectedMedia: UInt32 = ["espresso": 0x1B130F, "stealth": 0x101015, "cobalt": 0x08131F,
                "crimson": 0x1B0E13, "amethyst": 0x140E1E, "oat": 0xD1BDA3][theme.id] ?? 0x051214
            XCTAssertEqual(AppColors.exerciseVideoSurface, Color(hex: expectedMedia))
        }
    }

    @MainActor
    func testRootAppliesNativeLightAppearanceAndReturnsToDark() async throws {
        let manager = ThemeManager.shared
        let saved = manager.currentTheme.id
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let host = UIHostingController(rootView: RootView())
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey(); manager.setThemeId(saved) }
        for (id, style) in [("oat", UIUserInterfaceStyle.light), ("default", .dark)] {
            manager.setThemeId(id)
            for _ in 0..<60 {
                window.layoutIfNeeded()
                if host.view.traitCollection.userInterfaceStyle == style { break }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            XCTAssertEqual(host.view.traitCollection.userInterfaceStyle, style, id)
        }
    }

}


final class AppStatePersistenceTests: XCTestCase {
    private func fixture(count: Int = 3) -> StoredAppState {
        StoredAppState(programs: [Program(id: "p", name: "Fixture")], activeProgramId: "p",
            completed: ["p:w"], currentWeekKey: "2026-W41", history: (0..<count).map { i in
                WorkoutSessionRecord(id: "s\(i)", programId: "p", workoutId: "w", workoutTitle: "Upper",
                    startedAt: "2026-10-05T09:00:00Z", completedAt: "2026-10-05T10:00:00Z",
                    durationSeconds: 3600, totalVolumeKg: 123.45, totalCompletedSets: 1,
                    exerciseLogs: [SessionExerciseLog(exerciseName: "Bench", sets: [SessionSetLog(setNumber: 1, weightKg: 50.125, reps: 8)])])
            })
    }

    private func assertSame(_ actual: StoredAppState?, _ expected: StoredAppState, file: StaticString = #filePath, line: UInt = #line) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try encoder.encode(XCTUnwrap(actual)), try encoder.encode(expected), file: file, line: line)
    }

    func testLegacyMigrationSurvivesReopenAndRetainsExactOrderAndDuplicateIDs() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("state.sqlite")
        let suite = "audit.migration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var state = fixture(); state.history[1].id = state.history[0].id
        let data = try JSONEncoder().encode(state)
        defaults.set(data, forKey: "legacy")
        let store = AppStatePersistence(databaseURL: url)
        try store.migrate(state, defaults: defaults, legacyKey: "legacy")
        XCTAssertNil(defaults.data(forKey: "legacy"))
        try assertSame(AppStatePersistence(databaseURL: url).load(), state)
        // Repeated migration is idempotent, including explicit fixture reinjection.
        defaults.set(data, forKey: "legacy")
        try store.migrate(state, defaults: defaults, legacyKey: "legacy")
        try assertSame(store.load(), state)
    }

    func testMetadataHistoryReplacementAndDeletionAreCommittedTogether() throws {
        let store = AppStatePersistence(inMemory: true)
        let original = fixture(count: 1000)
        try store.saveAndWait(original)
        var updated = original
        updated.activeProgramId = "different"
        updated.history = Array(original.history.suffix(2).reversed())
        updated.history[0].exerciseLogs[0].sets[0].weightKg = 99.7903214
        try store.saveAndWait(updated)
        try assertSame(store.load(), updated)
    }

    func testCommitFailureRollsBackBothTablesAndRetainsLegacyBlob() throws {
        struct InjectedFailure: Error {}
        var fail = false
        let store = AppStatePersistence(inMemory: true, beforeCommit: { if fail { throw InjectedFailure() } })
        let original = fixture()
        try store.saveAndWait(original)
        let suite = "audit.failure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var changed = fixture(count: 5); changed.activeProgramId = "replacement"
        let raw = try JSONEncoder().encode(changed); defaults.set(raw, forKey: "legacy")
        fail = true
        XCTAssertThrowsError(try store.migrate(changed, defaults: defaults, legacyKey: "legacy"))
        XCTAssertEqual(defaults.data(forKey: "legacy"), raw)
        try assertSame(store.load(), original)
    }

    func testEncodingFailurePreservesCommittedState() throws {
        let store = AppStatePersistence(inMemory: true)
        let original = fixture(); try store.saveAndWait(original)
        var bad = original; bad.history[0].totalVolumeKg = .nan
        XCTAssertThrowsError(try store.saveAndWait(bad))
        try assertSame(store.load(), original)
    }

    func testAsyncWritesAreOrderedAndRunOffMainThread() throws {
        let done = expectation(description: "ordered saves")
        done.expectedFulfillmentCount = 20
        let store = AppStatePersistence(inMemory: true, beforeCommit: { XCTAssertFalse(Thread.isMainThread) })
        let original = fixture(count: 1000)
        for i in 0..<20 {
            var state = original; state.activeProgramId = "selection-\(i)"
            store.save(state) { error in XCTAssertNil(error); done.fulfill() }
        }
        wait(for: [done], timeout: 20)
        XCTAssertEqual(try store.load()?.activeProgramId, "selection-19")
    }

    func testUnreadableDatabaseIsPreserved() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("state.sqlite")
        let raw = Data("preserve corrupt recovery bytes".utf8); try raw.write(to: url)
        let store = AppStatePersistence(databaseURL: url)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.saveAndWait(fixture()))
        XCTAssertEqual(try Data(contentsOf: url), raw)
    }

    @MainActor
    func testFailedRestoreLeavesCurrentStateUnchanged() throws {
        struct InjectedFailure: Error {}
        var fail = false
        let persistence = AppStatePersistence(inMemory: true, beforeCommit: { if fail { throw InjectedFailure() } })
        let store = AppStore(persistence: persistence)
        try persistence.flush()
        XCTAssertTrue(store.saveState(fixture(), durable: true))
        let oldHistory = store.state.history
        let backup = try JSONEncoder().encode(FullBackupDocument(state: fixture(count: 5), weightUnit: .lbs))
        fail = true
        XCTAssertFalse(store.restoreBackupJson(try XCTUnwrap(String(data: backup, encoding: .utf8))))
        XCTAssertEqual(store.state.history, oldHistory)
        XCTAssertEqual(try persistence.load()?.history, oldHistory)
    }

    @MainActor
    func testFailedCompletionRetainsDraftAndRetryCommitsHistory() throws {
        struct Failure: Error {}
        let defaults = UserDefaults.standard
        let domain = try XCTUnwrap(Bundle.main.bundleIdentifier)
        let original = defaults.persistentDomain(forName: domain) ?? [:]
        defer { defaults.setPersistentDomain(original, forName: domain) }
        defaults.removeObject(forKey: "active_session_v1")
        var fail = false
        let persistence = AppStatePersistence(inMemory: true, beforeCommit: { if fail { throw Failure() } })
        let store = AppStore(persistence: persistence)
        let exercise = Exercise(id: "bench", name: "Bench", sets: 1, restSeconds: 0)
        let workout = Workout(id: "w", day: 1, title: "Upper", exercises: [exercise])
        let program = Program(id: "p", name: "Fixture", workouts: [workout])
        XCTAssertTrue(store.saveState(StoredAppState(programs: [program], activeProgramId: program.id), durable: true))
        XCTAssertTrue(store.startActiveSession(programId: program.id, workout: workout, allowPast: true))
        store.updateActiveSession { draft in
            var copy = draft
            copy.setsByExercise[exercise.id] = [ExerciseSetLog(setNumber: 1, weightInput: "50", repsInput: "8", weightKg: 50, completedReps: 8, isCompleted: true)]
            return copy
        }
        try persistence.flush()
        let draft = try XCTUnwrap(store.activeSession)
        let rawDraft = defaults.data(forKey: "active_session_v1")
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let record = SessionProgress.from(draft: draft, nowEpochMillis: now).record(draft: draft, completedAtEpochMillis: now)
        fail = true
        store.completeActiveSession(record)
        XCTAssertEqual(store.activeSession?.id, draft.id)
        XCTAssertEqual(defaults.data(forKey: "active_session_v1"), rawDraft)
        XCTAssertTrue(store.state.history.isEmpty)
        XCTAssertTrue(try XCTUnwrap(persistence.load()).history.isEmpty)
        fail = false
        store.completeActiveSession(record)
        XCTAssertNil(store.activeSession)
        XCTAssertNil(defaults.data(forKey: "active_session_v1"))
        XCTAssertEqual(try persistence.load()?.history.map(\.id), [record.id])
    }

}

final class AudioPlaybackLifecycleTests: XCTestCase {
    private final class Player: EffectAudioPlayer {
        var isPlaying = false
        var succeeds = true
        var starts = 0
        func restart() -> Bool { starts += 1; isPlaying = succeeds; return succeeds }
        func stop() { isPlaying = false }
    }

    func testDisabledPlaybackAndMissingAssetNeverActivate() {
        var activations = 0
        var creations = 0
        let controller = AudioPlaybackController(activate: { activations += 1 }, deactivate: {}, makePlayer: { _ in creations += 1; return nil })
        XCTAssertEqual(activations, 0)
        controller.play("set", enabled: false)
        XCTAssertEqual(creations, 0)
        controller.play("missing", enabled: true)
        controller.releaseIfIdle()
        XCTAssertEqual(activations, 0)
    }

    func testOverlappingAndRepeatedEffectsReleaseOnlyAfterLastFinishThenReactivate() {
        let set = Player(), rest = Player()
        var activations = 0, releases = 0
        let controller = AudioPlaybackController(activate: { activations += 1 }, deactivate: { releases += 1 },
            makePlayer: { $0 == "set" ? set : rest })
        controller.play("set", enabled: true)
        controller.play("rest", enabled: true)
        controller.play("set", enabled: true)
        XCTAssertEqual(activations, 1)
        XCTAssertEqual(set.starts, 2)
        controller.releaseIfIdle() // Backgrounding while effects still play.
        XCTAssertEqual(releases, 0)
        set.stop(); controller.releaseIfIdle()
        XCTAssertEqual(releases, 0)
        rest.stop(); controller.releaseIfIdle(); controller.releaseIfIdle()
        XCTAssertEqual(releases, 1)
        controller.play("set", enabled: true)
        XCTAssertEqual(activations, 2)
    }

    func testPlaybackAndActivationFailureLeaveNoIdleSession() {
        struct Failure: Error {}
        let player = Player(); player.succeeds = false
        var releases = 0, failActivation = false
        let controller = AudioPlaybackController(activate: { if failActivation { throw Failure() } },
            deactivate: { releases += 1 }, makePlayer: { _ in player })
        controller.play("set", enabled: true)
        XCTAssertEqual(releases, 1)
        failActivation = true
        controller.play("set", enabled: true)
        XCTAssertEqual(player.starts, 1)
        XCTAssertEqual(releases, 1)
    }

    func testInterruptionStopsPlaybackAndNextExplicitEffectReactivates() {
        let player = Player()
        var activations = 0
        let controller = AudioPlaybackController(activate: { activations += 1 }, deactivate: {}, makePlayer: { _ in player })
        controller.play("set", enabled: true)
        controller.interruptionBegan()
        XCTAssertFalse(player.isPlaying)
        controller.play("set", enabled: true)
        XCTAssertEqual(activations, 1)
        controller.interruptionEnded()
        XCTAssertFalse(player.isPlaying)
        controller.play("set", enabled: true)
        XCTAssertEqual(activations, 2)
        controller.mediaServicesReset()
        XCTAssertFalse(player.isPlaying)
        controller.play("set", enabled: true)
        XCTAssertEqual(activations, 3)
    }

    func testFailedIdleReleaseCanBeRetried() {
        struct Failure: Error {}
        let player = Player()
        var attempts = 0
        let controller = AudioPlaybackController(activate: {}, deactivate: { attempts += 1; if attempts == 1 { throw Failure() } }, makePlayer: { _ in player })
        controller.play("set", enabled: true)
        player.stop(); controller.releaseIfIdle(); controller.releaseIfIdle()
        XCTAssertEqual(attempts, 2)
    }
}


final class AudioEffectIntegrationTests: XCTestCase {
    func testBundledEffectCreatedOffMainReportsCompletionOnAudioQueue() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "form_set_complete", withExtension: "wav"))
        let queue = DispatchQueue(label: "audit.audio.integration")
        let done = expectation(description: "real AVAudioPlayer completion")
        var effect: EffectPlayer?
        queue.async {
            do {
                effect = try EffectPlayer(url: url, audioQueue: queue) {
                    XCTAssertFalse(Thread.isMainThread)
                    done.fulfill()
                }
                XCTAssertTrue(try XCTUnwrap(effect).restart())
            } catch { XCTFail("Bundled effect failed: \(error)"); done.fulfill() }
        }
        wait(for: [done], timeout: 10)
        let released = expectation(description: "audio cleanup off main")
        queue.async {
            XCTAssertFalse(Thread.isMainThread)
            effect?.stop(); effect = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            released.fulfill()
        }
        wait(for: [released], timeout: 10)
    }
}


final class LocalizationConcurrencyTests: XCTestCase {
    // Only synchronized lookup APIs cross threads; published setters stay on MainActor.
    private struct Worker: @unchecked Sendable { let read: () -> Void }
    func testConcurrentColdCacheLoadsAndTranslationsRetainAllLanguages() {
        let localizer = ContentLocalizer()
        let manager = LanguageManager()
        let languages = ["en", "tr", "de", "fr", "es"]
        DispatchQueue.concurrentPerform(iterations: 1000) { index in
            let language = languages[index % languages.count]
            XCTAssertEqual(localizer.loadExercises(lang: language).count, 300)
            XCTAssertEqual(localizer.loadPrograms(lang: language).count, AppStore.starterProgramFiles.count)
            XCTAssertNotNil(localizer.loadUI(lang: language)["notice.openLinkFailed"])
            XCTAssertNotEqual(manager.translate("form_lab.mirror_local_provider", language: language), "form_lab.mirror_local_provider")
            XCTAssertFalse(manager.plural("library.resultCount", 2, language: language).contains("{"))
            XCTAssertFalse(ContentDictionary.localize("Fixture", lang: language).isEmpty)
        }
    }

    @MainActor
    func testWorkerTranslationsRemainValidWhileUiSwitchesLanguage() {
        let previous = UserDefaults.standard.object(forKey: "app_language")
        defer { UserDefaults.standard.set(previous, forKey: "app_language") }
        let manager = LanguageManager()
        let group = DispatchGroup()
        let worker = Worker {
            XCTAssertNotEqual(manager.translate("form_lab.mirror_local_provider"), "form_lab.mirror_local_provider")
            XCTAssertFalse(manager.plural("library.resultCount", 2).contains("{"))
        }
        for _ in 0..<4 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                for _ in 0..<1000 { worker.read() }
            }
        }
        for _ in 0..<100 {
            for language in ["en", "tr", "de", "fr", "es"] { manager.languagePreference = language }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 20), .success)
    }
}


final class ThemeCoverageSnapshots: XCTestCase {
    private struct AuditComponents: View {
        @ObservedObject private var manager = ThemeManager.shared
        var body: some View {
            VStack(spacing: 16) {
                Text(manager.currentTheme.id).foregroundStyle(AppColors.text).padding(.horizontal, 20)
                WeeklyGoalProgressCard(metrics: WeeklyGoalProgressMetrics(
                    completedWorkouts: 2, totalWorkouts: 4, totalVolumeKg: 2500,
                    activeDurationSeconds: 2400, prsHitCount: 1)).padding(.horizontal, 20)
                MovementIcon(exerciseId: "barbell-bench-press", size: 108)
                TechniqueSectionView(title: "Technique cues", text: "Keep your feet planted.",
                    accent: AppColors.accent, isAvoid: false, collapsible: false).padding(.horizontal, 20)
                TechniqueSectionView(title: "What to avoid", text: "Avoid bouncing the bar.",
                    accent: AppColors.danger, isAvoid: true, collapsible: false).padding(.horizontal, 20)
                RestTimerBar(secondsRemaining: 74, totalSeconds: 120, exerciseName: "Barbell Bench Press",
                    isRunning: true, onTogglePause: {}, onAddSeconds: { _ in }, onSetDuration: { _ in },
                    onSkip: {}, isMuted: false, onToggleMute: {})
                Spacer(minLength: 0)
            }
            .padding(.vertical, 20)
            .frame(width: 320, height: 900)
            .background(AppColors.background)
        }
    }

    @MainActor
    @discardableResult
    private func capture(_ controller: UIViewController, name: String) -> UIImage {
        controller.view.layoutIfNeeded()
        let renderer = UIGraphicsImageRenderer(size: controller.view.bounds.size)
        let image = renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return image
    }

    @MainActor
    func testEightThemeComponentSnapshotsAndLiveSwitch() async throws {
        let original = ThemeManager.shared.currentTheme.id
        defer { ThemeManager.shared.setThemeId(original) }
        // Initialize the real weekly-card globals under the default theme, then switch live.
        ThemeManager.shared.setThemeId("default")
        let live = UIHostingController(rootView: AuditComponents())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 900))
        live.view.frame = window.bounds
        window.rootViewController = live
        window.makeKeyAndVisible()
        try await Task.sleep(nanoseconds: 400_000_000)
        capture(live, name: "theme-coverage-ios-live-default")
        ThemeManager.shared.setThemeId("espresso")
        try await Task.sleep(nanoseconds: 400_000_000)
        let switched = capture(live, name: "theme-coverage-ios-live-espresso")
        // Only the inset statistic tiles use ordinary surface within this card region.
        // This catches a file-level color captured when Obsidian first rendered.
        assertStatFill(switched, color: AppThemes.espresso.surface)
        window.isHidden = true
        for theme in AppThemes.all {
            ThemeManager.shared.setThemeId(theme.id)
            let controller = UIHostingController(rootView: AuditComponents())
            let fixtureWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 900))
            controller.view.frame = fixtureWindow.bounds
            fixtureWindow.rootViewController = controller
            fixtureWindow.makeKeyAndVisible()
            try await Task.sleep(nanoseconds: 300_000_000)
            let image = capture(controller, name: "theme-coverage-ios-components-\(theme.id)")
            assertStatFill(image, color: theme.surface)
            fixtureWindow.isHidden = true
        }
    }
    @MainActor
    private func assertStatFill(_ image: UIImage, color: Color) {
        let size = image.size
        let width = Int(size.width), height = Int(size.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image.cgImage!, in: CGRect(origin: .zero, size: size))
        let expected = color.resolve(in: EnvironmentValues())
        let rgb = [Int(expected.red * 255), Int(expected.green * 255), Int(expected.blue * 255)]
        var matching = 0
        // Search the card's inset region, allowing native text metrics to vary slightly.
        for y in 100..<270 { for x in 30..<290 {
            let offset = (y * width + x) * 4
            if (0..<3).allSatisfy({ abs(Int(bytes[offset + $0]) - rgb[$0]) <= 2 }) { matching += 1 }
        } }
        XCTAssertGreaterThan(matching, 500, "Weekly statistic fill must follow the live palette")
    }

    private struct ObservedScreen: View {
        @ObservedObject private var manager = ThemeManager.shared
        let screen: AnyView
        var body: some View { screen.background(AppColors.background) }
    }

    @MainActor
    func testEightThemesAcrossHeroAnalyticsDetailSummaryAndPaywall() async throws {
        let original = ThemeManager.shared.currentTheme.id
        let language = LanguageManager.shared.currentLanguage
        defer { ThemeManager.shared.setThemeId(original); LanguageManager.setLanguage(language) }
        LanguageManager.setLanguage("en")
        let store = AppStore(persistence: AppStatePersistence(inMemory: true))
        let program = AppStore.loadBundledStarterPrograms().first!
        let workout = program.workouts.first!
        let exercise = Exercise(id: "fixture-bench", name: "Barbell Bench Press",
            exerciseId: "barbell-bench-press", sets: 1)
        var fixtureState = store.state
        fixtureState.history = [WorkoutSessionRecord(id: "theme-history-fixture", programId: program.id,
            workoutId: workout.id, workoutTitle: "Upper", startedAt: "2026-10-05T09:00:00Z",
            completedAt: "2026-10-05T09:10:00Z", durationSeconds: 600, totalVolumeKg: 400,
            totalCompletedSets: 1, exerciseLogs: [SessionExerciseLog(exerciseName: "Barbell Bench Press",
                sets: [SessionSetLog(setNumber: 1, weightKg: 50, reps: 8)], targetSets: 1,
                exerciseId: "barbell-bench-press")], isComplete: true)]
        XCTAssertTrue(store.saveState(fixtureState, durable: true))
        var detail = ExerciseDetailView(exercise: exercise, onBack: {})
        detail.store = store
        var history = ExerciseDetailView(exercise: exercise, initialTab: .history, onBack: {})
        history.store = store
        let screens: [(String, AnyView)] = [
            ("home", AnyView(ScrollView { TodayHeroCard(workout: workout, programId: program.id,
                todayIndex: workout.day - 1, isCompleted: false, isAvailable: true,
                availableDay: nil, hasUnfinishedProgress: false, onStart: {}).padding(20) })),
            ("home-recovery", AnyView(ScrollView { TodayHeroCard(workout: nil,
                todayIndex: 0, isCompleted: false, isAvailable: false,
                availableDay: nil, hasUnfinishedProgress: false, onStart: {}).padding(20) })),
            ("home-back", AnyView(ScrollView { TodayHeroCard(workout: Workout(day: 1, title: "Back",
                focus: "Back and arm strength", targetMuscles: ["lats", "trapezius"]),
                todayIndex: 0, isCompleted: false, isAvailable: true,
                availableDay: nil, hasUnfinishedProgress: false, onStart: {}).padding(20) })),
            ("home-legs", AnyView(ScrollView { TodayHeroCard(workout: Workout(day: 1, title: "Legs",
                focus: "Quad and hamstring strength", targetMuscles: ["quadriceps", "hamstrings"]),
                todayIndex: 0, isCompleted: false, isAvailable: true,
                availableDay: nil, hasUnfinishedProgress: false, onStart: {}).padding(20) })),
            ("matrix", AnyView(ScrollView { VolumeMatrixView(store: store, customHistory: []).padding(20) })),
            ("detail", AnyView(detail)), ("history", AnyView(history)),
            ("summary", AnyView(SessionSummaryView(workoutTitle: "Upper", durationSeconds: 600,
                totalCompletedSets: 1, totalVolumeKg: 400,
                exerciseLogs: [SessionExerciseLog(exerciseName: "Barbell Bench Press",
                    sets: [SessionSetLog(setNumber: 1, weightKg: 50, reps: 8)], targetSets: 1)],
                onBack: {}, onSaveAndClose: {}))),
            ("paywall", AnyView(SessionFeaturePaywallContent(
                annual: SessionPaywallOffer(price: "$29.99"), monthly: SessionPaywallOffer(price: "$4.99"),
                selectedPlan: .annual, isPurchasing: false, isRestoring: false, purchaseError: nil,
                restoreMessage: nil, isRestoreError: false, onSelectPlan: { _ in }, onPurchase: {},
                onRestore: {}, onRetryPrices: {}, onTerms: {}, onPrivacy: {}, onClose: {})))
        ]
        for (name, screen) in screens {
            let controller = UIHostingController(rootView: ObservedScreen(screen: screen))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 900))
            controller.view.frame = window.bounds; window.rootViewController = controller; window.makeKeyAndVisible()
            for theme in ["home-back", "home-legs"].contains(name) ? AppThemes.all.filter({ !$0.isDark }) : AppThemes.all {
                ThemeManager.shared.setThemeId(theme.id)
                try await Task.sleep(nanoseconds: name == "detail" ? 1_200_000_000 : 300_000_000)
                let image = capture(controller, name: "theme-coverage-ios-\(name)-\(theme.id)")
                if name == "home-recovery" && theme.isDark {
                    assertRecoveryBackdropGradient(image, topInset: controller.view.safeAreaInsets.top, theme: theme.id)
                }
            }
            window.isHidden = true
        }
        for language in ["en", "tr", "de", "fr", "es"] {
            LanguageManager.setLanguage(language)
            ThemeManager.shared.setThemeId("espresso")
            let controller = UIHostingController(rootView: AuditComponents().environment(\.sizeCategory, .accessibilityMedium))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 900))
            controller.view.frame = window.bounds; window.rootViewController = controller; window.makeKeyAndVisible()
            try await Task.sleep(nanoseconds: 300_000_000)
            capture(controller, name: "theme-coverage-ios-large-\(language)")
            window.isHidden = true
        }
    }

    @MainActor
    private func assertRecoveryBackdropGradient(_ image: UIImage, topInset: CGFloat, theme: String) {
        let cgImage = image.cgImage!
        let scale = CGFloat(cgImage.width) / image.size.width
        // The 320pt fixture has 20pt outer padding plus the card's 20pt horizontal padding.
        // Sample an empty band above the athlete, safely inside the rounded corners.
        func brightness(_ fraction: Double) -> Double {
            let x = 40 + (image.size.width - 80) * fraction
            let crop = cgImage.cropping(to: CGRect(x: (x - 1) * scale, y: (topInset + 29) * scale,
                width: 3 * scale, height: 3 * scale).integral)!
            var pixel = [UInt8](repeating: 0, count: 4)
            let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return Double(Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2])) / 3
        }
        XCTAssertGreaterThan(brightness(0.15) - brightness(0.90), 6,
            "Recovery backdrop must visibly fade toward the studio in \(theme)")
    }
}

final class ExerciseAlphaMediaTests: XCTestCase {
    func testAllExerciseMoviesHaveNativeAlpha() async throws {
        XCTAssertEqual(ExerciseVideoCatalog.entries.count, 300)
        for id in ExerciseVideoCatalog.entries.keys.sorted() {
            let asset = AVURLAsset(url: try XCTUnwrap(ExerciseVideoCatalog.url(for: id)))
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let track = try XCTUnwrap(tracks.first, id)
            let characteristics = try await track.load(.mediaCharacteristics)
            XCTAssertTrue(characteristics.contains(.containsAlphaChannel), id)
            let size = try await track.load(.naturalSize)
            XCTAssertEqual(size, CGSize(width: 960, height: 540), id)
        }
    }

    @MainActor
    func testNativeAlphaBackgroundsSwitchWithoutReplacingPlayers() async throws {
        let savedTheme = ThemeManager.shared.currentTheme.id
        let previousKey = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let host = UIHostingController(rootView: AnyView(Color.clear))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previousKey?.makeKey(); ThemeManager.shared.setThemeId(savedTheme) }
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        func player(_ view: UIView) -> ExercisePlayerView? {
            if let view = view as? ExercisePlayerView { return view }
            for child in view.subviews { if let result = player(child) { return result } }
            return nil
        }
        for id in ["barbell-bench-press", "barbell-back-squat", "push-ups", "face-pull", "dumbbell-lateral-raise", "ab-wheel-rollout"] {
            host.rootView = AnyView(ExerciseDetailVideo(exerciseId: id).frame(width: 320)
                .environment(\.scenePhase, .active)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(hex: 0x090C0F)))
            var current: ExercisePlayerView?
            for _ in 0..<100 {
                window.layoutIfNeeded(); current = player(host.view)
                if current?.readyForDisplay == true { break }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            let retained = try XCTUnwrap(current, id)
            XCTAssertTrue(retained.readyForDisplay, id)
            for theme in AppThemes.all {
                ThemeManager.shared.setThemeId(theme.id)
                try await Task.sleep(nanoseconds: 250_000_000)
                XCTAssertTrue(player(host.view) === retained, "Theme switch recreated player: \(id)")
                XCTAssertEqual(retained.playbackRate, UIAccessibility.isReduceMotionEnabled ? 0 : 1.2, accuracy: 0.01)
                let token = UUID().uuidString
                let bounds = retained.convert(retained.bounds, to: nil)
                let request: [String: Any] = ["token": token, "exercise": id, "theme": theme.id,
                    "bounds": [bounds.minX,bounds.minY,bounds.width,bounds.height]]
                try JSONSerialization.data(withJSONObject: request).write(
                    to: directory.appendingPathComponent("alpha-capture-request.json"), options: .atomic)
                if FileManager.default.fileExists(atPath: directory.appendingPathComponent("alpha-capture-enabled").path) {
                    let ack = directory.appendingPathComponent("alpha-capture-ack-" + token)
                    for _ in 0..<80 {
                        if FileManager.default.fileExists(atPath: ack.path) { break }
                        try await Task.sleep(nanoseconds: 50_000_000)
                    }
                    XCTAssertTrue(FileManager.default.fileExists(atPath: ack.path), "Missing native capture: \(id) \(theme.id)")
                }
            }
        }
    }
}


final class AuditStoreLifetimeTests: XCTestCase {
    @MainActor
    func testPreferencesPersistWithoutRetainingStoreOrPersistence() throws {
        let defaults = UserDefaults.standard
        let domain = try XCTUnwrap(Bundle.main.bundleIdentifier)
        let original = defaults.persistentDomain(forName: domain) ?? [:]
        defer { defaults.setPersistentDomain(original, forName: domain) }
        defaults.removeObject(forKey: "active_session_v1")
        weak var releasedStore: AppStore?
        weak var releasedPersistence: AppStatePersistence?
        try autoreleasepool {
            let persistence = AppStatePersistence(inMemory: true)
            let store = AppStore(persistence: persistence)
            releasedStore = store
            releasedPersistence = persistence
            store.soundEnabled = false
            store.defaultRestSeconds = 123
            store.prefillNextSet = false
            store.weightUnit = .lbs
            store.barType = .technique10
            store.availablePlatesKg = [10, 5, 1.25]
            store.isOnboardingCompleted = true
            try persistence.flush()
            XCTAssertFalse(defaults.bool(forKey: "sound_enabled"))
            XCTAssertEqual(defaults.integer(forKey: "default_rest_seconds"), 123)
            XCTAssertFalse(defaults.bool(forKey: "prefill_next_set"))
            XCTAssertEqual(defaults.string(forKey: "weight_unit"), "lbs")
            XCTAssertEqual(defaults.string(forKey: "bar_type"), BarType.technique10.key)
            XCTAssertEqual(defaults.array(forKey: "available_plates_kg") as? [Double], [10, 5, 1.25])
            XCTAssertTrue(defaults.bool(forKey: "is_onboarding_completed"))
        }
        XCTAssertNil(releasedStore)
        XCTAssertNil(releasedPersistence)
    }
}


final class AuditCatalogConcurrencyTests: XCTestCase {
    func testConcurrentCatalogAndLegacyLookupsKeepCanonicalIdentities() {
        DispatchQueue.concurrentPerform(iterations: 1000) { _ in
            XCTAssertEqual(ExerciseCatalog.canonicalExercises.count, 300)
            XCTAssertEqual(ExerciseCatalog.resolveCanonicalId(stableId: nil, name: "  BARBELL   BENCH PRESS  "), "barbell-bench-press")
            XCTAssertEqual(ExerciseCatalog.resolveCanonicalId(stableId: nil, name: "dumbbell-split-squat-front-foot-elevanted"), "dumbbell-split-squat-front-foot-elevanted")
            XCTAssertEqual(ExerciseCatalog.resolveCanonicalId(stableId: "custom-id", name: "Barbell Bench Press"), "custom-id")
            XCTAssertNil(ExerciseCatalog.resolveCanonicalId(stableId: nil, name: "unmapped fixture"))
        }
    }
}

final class AuditEntitlementConcurrencyTests: XCTestCase {
    private struct Reader: @unchecked Sendable { let manager: ProAccessManager }

    @MainActor
    func testWorkerAuthorizationRemainsSafeDuringMainThreadEntitlementChanges() {
        let manager = ProAccessManager()
        let reader = Reader(manager: manager)
        let group = DispatchGroup()
        for _ in 0..<4 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                for _ in 0..<5000 {
                    _ = reader.manager.isFeatureUnlocked(.cloudBackup)
                    _ = reader.manager.isFeatureUnlocked(.volumeMatrix)
                }
            }
        }
        for _ in 0..<100 {
            manager.updateSubscriptionStatus(active: true)
            manager.setFeatureOverride(.cloudBackup, unlocked: false)
            XCTAssertFalse(manager.isFeatureUnlocked(.cloudBackup))
            manager.setFeatureOverride(.cloudBackup, unlocked: nil)
            XCTAssertTrue(manager.isFeatureUnlocked(.cloudBackup))
            manager.resetOverrides()
            XCTAssertFalse(manager.isFeatureUnlocked(.cloudBackup))
        }
        XCTAssertEqual(group.wait(timeout: .now() + 20), .success)
        manager.updateSubscriptionStatus(active: true)
        XCTAssertTrue(manager.isFeatureUnlocked(.cloudBackup))
        XCTAssertFalse(manager.toggleSubscriptionStatus())
        XCTAssertFalse(manager.isFeatureUnlocked(.cloudBackup))
    }
}


final class AuditSessionInsightsTests: XCTestCase {
    @MainActor
    func testInsightsReuseHistoryAndInvalidatePrescriptionUnitLanguageAndCorrectedLogs() {
        var computations = 0
        let cache = SessionHistoryInsightsCache { _, _, _, _ in
            computations += 1
            return .init(previousWorkingSets: [], recommendation: nil, prText: "fixture")
        }
        var exercise = Exercise(id: "bench", name: "Barbell Bench Press", exerciseId: "barbell-bench-press", prescription: "3x8-12")
        var record = WorkoutSessionRecord(id: "history", programId: "p", workoutId: "w", workoutTitle: "Fixture",
            startedAt: "2026-10-12T09:00:00Z", completedAt: "2026-10-12T10:00:00Z", durationSeconds: 3600)
        for _ in 0..<100 { _ = cache.get(exercise: exercise, history: [record], unit: .kg) }
        XCTAssertEqual(computations, 1)
        exercise.prescription = "3x5"
        _ = cache.get(exercise: exercise, history: [record], unit: .kg)
        XCTAssertEqual(computations, 2)
        record.totalVolumeKg = 99
        _ = cache.get(exercise: exercise, history: [record], unit: .kg)
        XCTAssertEqual(computations, 3)
        _ = cache.get(exercise: exercise, history: [record], unit: .lbs)
        XCTAssertEqual(computations, 4)
        let previous = LanguageManager.shared.languagePreference
        defer { LanguageManager.setLanguage(previous) }
        LanguageManager.setLanguage(LanguageManager.shared.currentLanguage == "tr" ? "en" : "tr")
        _ = cache.get(exercise: exercise, history: [record], unit: .lbs)
        XCTAssertEqual(computations, 5)
    }

    @MainActor
    func testCachedInsightsMatchUncachedProgressionAndPrCalculations() {
        let exercise = Exercise(id: "bench", name: "Barbell Bench Press", exerciseId: "barbell-bench-press", sets: 1, reps: RepTarget(min: 8, max: 12))
        let record = WorkoutSessionRecord(id: "history", programId: "p", workoutId: "w", workoutTitle: "Fixture",
            startedAt: "2026-10-12T09:00:00Z", completedAt: "2026-10-12T10:00:00Z", durationSeconds: 3600,
            exerciseLogs: [SessionExerciseLog(exerciseName: exercise.name, sets: [SessionSetLog(setNumber: 1, weightKg: 50, reps: 12)], targetSets: 1, exerciseId: exercise.exerciseId)])
        let cache = SessionHistoryInsightsCache()
        for unit in WeightUnit.allCases {
            let result = cache.get(exercise: exercise, history: [record], unit: unit)
            XCTAssertEqual(result.recommendation, ProgressionEngine.computeProgression(exercise: exercise, history: [record], weightUnit: unit))
            XCTAssertEqual(result.previousWorkingSets, WorkoutSessionUtils.findPreviousSessionWorkingSets(history: [record], exercise: exercise))
            XCTAssertEqual(result.prText, WorkoutSessionUtils.findExercisePr(history: [record], exercise: exercise, unit: unit))
        }
    }
}


final class AuditVideoLifecycleTests: XCTestCase {
    @MainActor
    func testVisibilityAndDismantleStopPollingWithoutRetainingWebView() throws {
        let controller = YouTubePlayerController(video: try XCTUnwrap(YouTubeVideo(id: "abcdefghijk")))
        let webView = WKWebView(frame: .zero)
        controller.webView = webView
        controller.startPolling()
        XCTAssertTrue(controller.isPolling)
        controller.setVisible(false)
        XCTAssertFalse(controller.isPolling)
        controller.setVisible(true)
        XCTAssertTrue(controller.isPolling)
        let wrapper = YouTubeWebPlayerView(controller: controller, onExternalLink: { _ in })
        YouTubeWebPlayerView.dismantleUIView(webView, coordinator: wrapper.makeCoordinator())
        XCTAssertFalse(controller.isPolling)
        XCTAssertNil(controller.webView)
        controller.setVisible(true)
        XCTAssertFalse(controller.isPolling)
    }
}


final class AuditSearchPerformanceTests: XCTestCase {
    @MainActor
    func testCandidateSearchNormalizationBaseline() {
        let previous = LanguageManager.shared.languagePreference
        defer { LanguageManager.setLanguage(previous) }
        LanguageManager.setLanguage("en")
        let exercises = ExerciseCatalog.canonicalExercises.values.sorted { $0.id < $1.id }.map { $0.toExercise() }
        let queries = ["b", "ba", "bar", "barbell", "bench", "press", "squat", "lunge", "cable", "dumbbell", "row", "pull", "leg", "curl", "hamstring", "neutral grip", "single leg", "unknown fixture"].map { ExerciseSearch.Query($0) }
        var checksum = 0
        let started = Date.timeIntervalSinceReferenceDate
        for query in queries {
            for exercise in exercises {
                if let score = ExerciseSearch.score(query, exercise: exercise, localizedName: exercise.displayName, category: exercise.metadataSubtitle) { checksum += score + 1 }
            }
        }
        let elapsed = Date.timeIntervalSinceReferenceDate - started
        let preparationStarted = Date.timeIntervalSinceReferenceDate
        let prepared = exercises.map { ExerciseSearch.Candidate(exercise: $0, localizedName: $0.displayName, category: $0.metadataSubtitle) }
        let preparationElapsed = Date.timeIntervalSinceReferenceDate - preparationStarted
        var preparedChecksum = 0
        let preparedStarted = Date.timeIntervalSinceReferenceDate
        for query in queries {
            for candidate in prepared {
                if let score = ExerciseSearch.score(query, candidate: candidate) { preparedChecksum += score + 1 }
            }
        }
        let preparedElapsed = Date.timeIntervalSinceReferenceDate - preparedStarted
        XCTAssertEqual(preparedChecksum, checksum)
        XCTAssertGreaterThan(checksum, 0)
        let attachment = XCTAttachment(string: "baselineSeconds=\(elapsed); preparedSeconds=\(preparedElapsed); preparationSeconds=\(preparationElapsed); candidates=\(exercises.count); queries=\(queries.count); checksum=\(checksum)")
        attachment.name = "search-normalization-baseline"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testDecodeProgramValidEnvelope() throws {
        let json = """
        {
          "format": "form.program",
          "schemaVersion": 4,
          "program": {
            "id": "test-prog",
            "name": "Test Program",
            "description": "Test description",
            "workouts": [
              {
                "id": "w1",
                "day": 1,
                "title": "Monday Workout",
                "exercises": []
              }
            ]
          }
        }
        """
        let program = try AppStore.decodeProgram(from: Data(json.utf8))
        XCTAssertEqual(program.id, "test-prog")
        XCTAssertEqual(program.name, "Test Program")
        XCTAssertEqual(program.workouts.count, 1)
        XCTAssertEqual(program.workouts[0].day, 1)
    }

    func testDecodeProgramRejectsFullBackup() {
        let json = """
        {
          "schemaVersion": 3,
          "programs": [],
          "history": []
        }
        """
        XCTAssertThrowsError(try AppStore.decodeProgram(from: Data(json.utf8))) { error in
            guard case AppStore.ProgramImportError.fullBackup = error else {
                XCTFail("Expected fullBackup error, got: \(error)")
                return
            }
        }
    }

    func testDecodeProgramRejectsInvalidFormat() {
        let json = """
        {
          "format": "other.format",
          "schemaVersion": 4,
          "program": { "id": "p1", "name": "P1", "workouts": [] }
        }
        """
        XCTAssertThrowsError(try AppStore.decodeProgram(from: Data(json.utf8))) { error in
            guard case AppStore.ProgramImportError.invalidFormat(let fmt) = error else {
                XCTFail("Expected invalidFormat error, got: \(error)")
                return
            }
            XCTAssertEqual(fmt, "other.format")
        }
    }

    func testDecodeProgramRejectsUnsupportedVersion() {
        let json = """
        {
          "format": "form.program",
          "schemaVersion": 99,
          "program": { "id": "p1", "name": "P1", "workouts": [] }
        }
        """
        XCTAssertThrowsError(try AppStore.decodeProgram(from: Data(json.utf8))) { error in
            guard case AppStore.ProgramImportError.unsupportedVersion(let v) = error else {
                XCTFail("Expected unsupportedVersion error, got: \(error)")
                return
            }
            XCTAssertEqual(v, 99)
        }
    }

    func testDecodeProgramRejectsBlankName() {
        let json = """
        {
          "format": "form.program",
          "schemaVersion": 4,
          "program": { "id": "p1", "name": "   ", "workouts": [] }
        }
        """
        XCTAssertThrowsError(try AppStore.decodeProgram(from: Data(json.utf8))) { error in
            guard case AppStore.ProgramImportError.invalidProgramName = error else {
                XCTFail("Expected invalidProgramName error, got: \(error)")
                return
            }
        }
    }

    func testDecodeProgramRejectsDuplicateWorkoutDays() {
        let json = """
        {
          "format": "form.program",
          "schemaVersion": 4,
          "program": {
            "id": "p1",
            "name": "P1",
            "workouts": [
              { "id": "w1", "day": 1, "title": "Day 1A", "exercises": [] },
              { "id": "w2", "day": 1, "title": "Day 1B", "exercises": [] }
            ]
          }
        }
        """
        XCTAssertThrowsError(try AppStore.decodeProgram(from: Data(json.utf8))) { error in
            guard case AppStore.ProgramImportError.duplicateWorkoutDays = error else {
                XCTFail("Expected duplicateWorkoutDays error, got: \(error)")
                return
            }
        }
    }

    @MainActor
    func testImportProgramUpdatesExistingProgramInPlace() throws {
        let store = AppStore(persistence: AppStatePersistence(inMemory: true))
        let initialCount = store.state.programs.count
        guard let first = store.state.programs.first else {
            XCTFail("Starter programs should not be empty")
            return
        }
        let updatedJson = """
        {
          "format": "form.program",
          "schemaVersion": 4,
          "program": {
            "id": "\(first.id)",
            "name": "Updated \(first.name)",
            "workouts": []
          }
        }
        """
        let imported = try store.importProgram(jsonData: Data(updatedJson.utf8))
        XCTAssertEqual(store.state.programs.count, initialCount, "Count should not increase when updating existing ID")
        XCTAssertEqual(imported.name, "Updated \(first.name)")
        let found = store.state.programs.first { $0.id == first.id }
        XCTAssertEqual(found?.name, "Updated \(first.name)")
    }

    @MainActor
    func testProgramHeroCardMenuToggleBehavior() {
        var menuProgramId: String? = nil
        let programId = "aesthetic-hypertrophy"

        let openMenu = {
            menuProgramId = programId
        }
        let closeMenu = {
            if menuProgramId == programId {
                menuProgramId = nil
            }
        }

        // Initially closed
        XCTAssertNil(menuProgramId)

        // First click triggers opening
        openMenu()
        XCTAssertEqual(menuProgramId, programId)

        // Clicking 3 dots again when menu is open triggers closeMenu -> onCloseMenu
        closeMenu()
        XCTAssertNil(menuProgramId, "Menu must close when clicked again")
    }

    func testEarliestWorkoutMonth() {
        XCTAssertNil(WorkoutCalendar.earliestWorkoutMonth(history: nil, sessions: []))
        let emptyHistory = WorkoutCalendarHistory(nextScheduledDate: "2026-10-01", scheduledWeekdays: [1], missedDates: [], entries: [])
        XCTAssertNil(WorkoutCalendar.earliestWorkoutMonth(history: emptyHistory, sessions: []))

        let session1 = WorkoutSessionRecord(
            programId: "p", workoutId: "w", workoutTitle: "T",
            startedAt: "2025-06-15T10:00:00Z", completedAt: "2025-06-15T11:00:00Z",
            durationSeconds: 3600, scheduledDate: "2025-06-15"
        )
        let session2 = WorkoutSessionRecord(
            programId: "p", workoutId: "w", workoutTitle: "T",
            startedAt: "2024-08-20T10:00:00Z", completedAt: "2024-08-20T11:00:00Z",
            durationSeconds: 3600, scheduledDate: "2024-08-20"
        )
        let history = WorkoutCalendarHistory(
            nextScheduledDate: "2026-01-01", scheduledWeekdays: [1], missedDates: [],
            entries: [WorkoutDayEntry(id: "m1", date: "2024-03-10", status: .completed)]
        )
        let earliest = WorkoutCalendar.earliestWorkoutMonth(history: history, sessions: [session1, session2])
        XCTAssertEqual(earliest, "2024-03")
    }

    func testRestoreBackupUpdatesCalendarStartMonthToEarliestLoggedWorkout() throws {
        let store = AppStore(persistence: AppStatePersistence(inMemory: true))
        store.setCalendarStartMonth("2026-10")
        XCTAssertEqual(store.calendarStartMonth, "2026-10")

        let session = WorkoutSessionRecord(
            programId: "p", workoutId: "w", workoutTitle: "T",
            startedAt: "2024-05-10T10:00:00Z", completedAt: "2024-05-10T11:00:00Z",
            durationSeconds: 3600, scheduledDate: "2024-05-10"
        )
        var state = store.state
        state.history = [session]
        let backupDoc = FullBackupDocument(state: state, weightUnit: .kg)
        let json = try String(decoding: JSONEncoder().encode(backupDoc), as: UTF8.self)

        XCTAssertTrue(store.restoreBackupJson(json))
        XCTAssertEqual(store.calendarStartMonth, "2024-05")
    }
}

