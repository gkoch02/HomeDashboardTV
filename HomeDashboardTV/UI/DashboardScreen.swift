import DashboardCore
import SwiftUI

/// The root: the dashboard, or a placeholder until the first snapshot, with settings over it.
/// A click opens settings; Menu closes them. Left and right step through the layouts.
///
/// Focus and the click handler belong to the dashboard layer alone, never to a container that
/// also holds the settings panel: on tvOS a non-focusable ancestor took the panel's buttons
/// out of the focus engine with it, so the panel showed but the remote could not reach it.
/// While the panel is open the dashboard is not focusable; when it shuts, the dashboard claims
/// focus back (on the next run-loop turn, once it is focusable again), as IdleHoursTV does.
struct DashboardScreen: View {
    @Environment(DashboardStore.self) private var store
    @FocusState private var screenFocused: Bool

    var body: some View {
        ZStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focusable(!store.settingsVisible)
                .focused($screenFocused)
                .onTapGesture { if !store.settingsVisible { store.settingsVisible = true } }
                .onMoveCommand { direction in
                    guard !store.settingsVisible else { return }
                    switch direction {
                    case .left: store.layout = store.layout.advanced(by: -1)
                    case .right: store.layout = store.layout.advanced(by: 1)
                    default: break
                    }
                }
                .accessibilityIdentifier("dashboard")
            if store.settingsVisible {
                SettingsView()
                    .transition(.opacity)
            }
        }
        .background(Color(red: 0.05, green: 0.06, blue: 0.09))
        .animation(.easeInOut(duration: 0.25), value: store.settingsVisible)
        .onAppear { claimFocus() }
        .onChange(of: store.settingsVisible) { _, _ in claimFocus() }
    }

    private func claimFocus() {
        guard !store.settingsVisible else { return }
        DispatchQueue.main.async { screenFocused = true }
    }

    private var content: some View {
            TimelineView(.everyMinute) { context in
                if let snapshot = store.snapshot {
                    switch store.layout {
                    case .dashboard: frame(DashboardView.self, snapshot, context.date)
                    case .agenda: frame(AgendaPlateView.self, snapshot, context.date)
                    case .moon: frame(MoonView.self, snapshot, context.date)
                    case .horizon: frame(HorizonView.self, snapshot, context.date)
                    }
                } else if store.connection != nil {
                    Waiting(problem: store.problem)
                }
            }
    }

    private func frame<T: Theme>(_ theme: T.Type, _ snapshot: Snapshot, _ now: Date) -> some View {
        ThemeFrame(theme: T(snapshot: snapshot, now: now), now: now, notice: notice(now: now))
    }

    /// One line for the corner: the connection is down, or a source the Pi is still showing has
    /// gone stale. Nothing when everything is current.
    private func notice(now: Date) -> String? {
        if let since = store.failingSince {
            return "Can't reach the dashboard since \(since.formatted(date: .omitted, time: .shortened))"
        }
        guard let sources = store.snapshot?.sources else { return nil }
        let stale = [
            ("Calendar", sources.events?.staleness),
            ("Weather", sources.weather?.staleness),
            ("Birthdays", sources.birthdays?.staleness),
        ].filter { $0.1?.isWorthFlagging == true }.map(\.0)
        return stale.isEmpty ? nil : "\(ListFormatter.localizedString(byJoining: stale)) not updated lately"
    }
}

private struct Waiting: View {
    let problem: String?

    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
            Text(problem ?? "Reading the dashboard…")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            if problem != nil {
                Text("Click to change where the dashboard comes from.")
                    .font(.system(size: 26))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
