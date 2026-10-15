import SwiftUI

@main
struct HomeDashboardApp: App {
    @State private var store = DashboardStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            DashboardScreen()
                .environment(store)
                // A wall display: the screensaver stays away for as long as "Keep awake" says.
                .onAppear { store.start() }
                // The press that brought the app back counts as one.
                .onChange(of: scenePhase) { _, phase in if phase == .active { store.noteInteraction() } }
        }
    }
}
