import SwiftUI

@main
struct HomeDashboardApp: App {
    @State private var store = DashboardStore()

    var body: some Scene {
        WindowGroup {
            DashboardScreen()
                .environment(store)
                .onAppear {
                    // A wall display: the screensaver must not take over.
                    UIApplication.shared.isIdleTimerDisabled = true
                    store.start()
                }
        }
    }
}
