import DashboardCore
import SwiftUI

/// The root: the dashboard, or a placeholder until the first snapshot, with settings over it.
/// A click opens settings; Menu closes them.
struct DashboardScreen: View {
    @Environment(DashboardStore.self) private var store

    var body: some View {
        ZStack {
            TimelineView(.everyMinute) { context in
                if let snapshot = store.snapshot {
                    DashboardView(snapshot: snapshot, now: context.date, notice: notice(now: context.date))
                } else if store.connection != nil {
                    Waiting(problem: store.problem)
                }
            }
            if store.settingsVisible {
                SettingsView()
                    .transition(.opacity)
            }
        }
        .background(Palette.night)
        .focusable(!store.settingsVisible)
        .onTapGesture { store.settingsVisible = true }
        .animation(.easeInOut(duration: 0.25), value: store.settingsVisible)
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
