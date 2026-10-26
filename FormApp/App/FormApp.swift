import SwiftUI
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        RestAlertScheduler.shared.install()
        RestAlertScheduler.shared.shouldDeferPrompt = { MainActor.assumeIsolated { TourController.shared.progress.shouldStart(.restTimer) } }
        return true
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        // Info.plist lists landscape for open foldables; every other iPhone stays portrait.
        FoldState.shared.supportedOrientations(
            onScreen: window?.screen.bounds.size, isPhone: UIDevice.current.userInterfaceIdiom == .phone
        )
    }
}

@main
struct FormApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        _ = FormAudioPlayer.shared
        // Restore the cached entitlement before the first view applies a premium theme.
        _ = StoreKitSubscriptionManager.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
