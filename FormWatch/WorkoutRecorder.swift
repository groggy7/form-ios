import Foundation
import HealthKit
import WatchKit

/// Records the iPhone workout as an Apple Health strength workout on the watch (docs/apple-watch.md, phase 2).
/// `WatchSnapshot.workoutStep` decides what to do; this class carries out one step at a time on the main thread.
/// While it records, the workout session keeps the app in front on wrist raise and running in the background.
final class WorkoutRecorder: NSObject, ObservableObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    static let shared = WorkoutRecorder()
    private static let sessionIdKey = "watch_workout_session_id_v1"
    private static let startedAtKey = "watch_workout_started_at_v1"

    @Published private(set) var heartRate: Int?
    @Published private(set) var isRecording = false
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var isBusy = false
    /// Workouts that could not be recorded, for example without Health access; never retried.
    private var skipped = Set<String>()

    /// Kept for a workout recovered after the app ends, so it still matches its iPhone workout.
    private var sessionId: String? {
        get { UserDefaults.standard.string(forKey: Self.sessionIdKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.sessionIdKey) }
    }
    private var startedAt: Int64 {
        get { Int64(UserDefaults.standard.double(forKey: Self.startedAtKey)) }
        set { UserDefaults.standard.set(Double(newValue), forKey: Self.startedAtKey) }
    }

    private var running: RunningWorkout? { session == nil ? nil : RunningWorkout(sessionId: sessionId, startedAt: startedAt) }

    /// Called whenever an iPhone snapshot arrives, and again after each step.
    func update(for snapshot: WatchSnapshot?) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !isBusy, let step = snapshot?.workoutStep(running: running, skipped: skipped) else { return }
        switch step {
        case .adopt(let id): sessionId = id
        case .start(let id): begin(sessionId: id)
        case .finish(let save, let endedAt): end(save: save, endedAt: endedAt)
        }
    }

    /// Opening the app is not an entitlement: only an eligible iPhone snapshot can start recording.
    func startFromIPhone() {
        dispatchPrecondition(condition: .onQueue(.main))
        WatchStore.shared.send(.refresh)
        update(for: WatchStore.shared.snapshot)
    }

    /// Reattaches a workout that was running when the app ended.
    func recover() {
        healthStore.recoverActiveWorkoutSession { session, error in
            DispatchQueue.main.async {
                guard let session else {
                    if let error { print("Workout recovery failed: \(error)") }
                    return
                }
                self.attach(session)
                self.update(for: WatchStore.shared.snapshot)
            }
        }
    }

    private func eligibleStart(_ id: String) -> Bool {
        WatchStore.shared.snapshot?.workoutStep(running: nil, skipped: skipped) == .start(sessionId: id)
    }

    private func begin(sessionId id: String) {
        guard eligibleStart(id) else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            skipped.insert(id)
            return
        }
        isBusy = true
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        healthStore.requestAuthorization(toShare: [HKObjectType.workoutType()], read: read) { _, _ in
            DispatchQueue.main.async { self.startSession(sessionId: id) }
        }
    }

    private func startSession(sessionId id: String) {
        defer {
            isBusy = false
            update(for: WatchStore.shared.snapshot)
        }
        // A permission prompt can outlive the entitlement, recording setting or workout it was opened for.
        guard eligibleStart(id) else { return }
        // Declining Health access leaves the watch app as a remote for the iPhone workout.
        guard healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
            skipped.insert(id)
            return
        }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            session.associatedWorkoutBuilder().dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            let start = Date()
            sessionId = id
            startedAt = WatchSync.nowMillis(start)
            attach(session)
            session.startActivity(with: start)
            builder?.beginCollection(withStart: start) { _, error in
                if let error { print("Workout collection failed to begin: \(error)") }
            }
        } catch {
            print("Workout session failed to start: \(error)")
            skipped.insert(id)
        }
    }

    /// Ends at the iPhone's end time, kept after the start and not in the future.
    private func end(save: Bool, endedAt: Int64?) {
        guard let session, let builder else { return }
        isBusy = true
        let end = min(max(endedAt ?? WatchSync.nowMillis(), startedAt + 1000), WatchSync.nowMillis())
        session.end()
        builder.endCollection(withEnd: Date(timeIntervalSince1970: Double(end) / 1000)) { _, error in
            if let error { print("Workout collection failed to end: \(error)") }
            let done = {
                DispatchQueue.main.async {
                    self.detach()
                    self.isBusy = false
                    self.update(for: WatchStore.shared.snapshot)
                }
            }
            guard save else {
                builder.discardWorkout()
                done()
                return
            }
            builder.finishWorkout { _, error in
                if let error { print("Workout failed to save: \(error)") }
                done()
            }
        }
    }

    private func attach(_ session: HKWorkoutSession) {
        self.session = session
        builder = session.associatedWorkoutBuilder()
        session.delegate = self
        builder?.delegate = self
        isRecording = true
    }

    private func detach() {
        session = nil
        builder = nil
        sessionId = nil
        heartRate = nil
        isRecording = false
    }

    // MARK: HKWorkoutSessionDelegate and HKLiveWorkoutBuilderDelegate (called on background queues)

    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {}

    /// A failed session has nothing left to save; the next snapshot may start a new one.
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("Workout session failed: \(error)")
        DispatchQueue.main.async {
            guard self.session === workoutSession else { return }
            self.detach()
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let heartRateType = HKQuantityType(.heartRate)
        guard collectedTypes.contains(heartRateType),
              let quantity = workoutBuilder.statistics(for: heartRateType)?.mostRecentQuantity() else { return }
        let bpm = Int(quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())).rounded())
        DispatchQueue.main.async { self.heartRate = bpm }
    }
}
