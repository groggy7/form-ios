import HealthKit
import SwiftUI
import WatchKit

/// Receives the workout the iPhone starts with `startWatchApp`, and a workout running when the app ended.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        WorkoutRecorder.shared.startFromIPhone()
    }

    func handleActiveWorkoutRecovery() {
        WorkoutRecorder.shared.recover()
    }
}

@main
struct FormWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
    @StateObject private var store = WatchStore.shared

    init() {
        WatchStore.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView(store: store)
        }
    }
}
