import SwiftUI

@main
struct FormWatchApp: App {
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
