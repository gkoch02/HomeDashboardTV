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
    /// The fade through black between layouts: how much of the layout shows (it falls to 0,
    /// the layout changes, it rises to 1), and the layout the presses so far lead to.
    @State private var shown: CGFloat = 1
    @State private var target: DashboardStore.Layout?
    /// Counts fades, so one cut short by the next press does not act when it finishes.
    @State private var fade = 0

    var body: some View {
        ZStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focusable(!store.settingsVisible)
                .focused($screenFocused)
                .onTapGesture {
                    store.noteInteraction()
                    if !store.settingsVisible { store.settingsVisible = true }
                }
                .onMoveCommand { direction in
                    guard !store.settingsVisible else { return }
                    store.noteInteraction()
                    switch direction {
                    case .left: change(by: -1)
                    case .right: change(by: 1)
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

    /// Steps the layout through black: the screen fades out, the layout changes while it is
    /// dark, and the new one fades in. Presses during the fade add up, and the screen comes up
    /// on where they lead.
    private func change(by steps: Int) {
        let next = (target ?? store.layout).advanced(by: steps)
        target = next
        fade += 1
        let this = fade
        withAnimation(.easeIn(duration: FadeThroughBlack.half)) {
            shown = 0
        } completion: {
            guard fade == this else { return }
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { store.layout = next }
            target = nil
            withAnimation(.easeOut(duration: FadeThroughBlack.half)) { shown = 1 }
        }
    }

    private func claimFocus() {
        guard !store.settingsVisible else { return }
        DispatchQueue.main.async { screenFocused = true }
    }

    private var content: some View {
            TimelineView(.everyMinute) { context in
                if let snapshot = store.snapshot {
                    layout(store.layout, snapshot, context.date)
                        .id(store.layout)
                        .opacity(shown)
                        .background { Color.black.ignoresSafeArea() }
                } else if store.connection != nil {
                    Waiting(problem: store.problem)
                }
            }
    }

    @ViewBuilder private func layout(_ layout: DashboardStore.Layout, _ snapshot: Snapshot, _ now: Date) -> some View {
                    switch layout {
                    case .dashboard: frame(DashboardView.self, snapshot, now)
                    case .agenda: frame(AgendaPlateView.self, snapshot, now)
                    case .moon: frame(MoonView.self, snapshot, now)
                    case .horizon: frame(HorizonView.self, snapshot, now)
                    case .light: frame(LightCycleView.self, snapshot, now)
                    case .quote: frame(QuoteView.self, snapshot, now)
                    case .night: frame(NightView.self, snapshot, now)
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

/// Moving between layouts with the remote: a fade through black. Driven by one animated
/// opacity on the layout, not by SwiftUI transitions, whose implicit animation also animated
/// each layout's insides as it was laid out.
private enum FadeThroughBlack {
    /// Each half: out to black, then in from it.
    static let half = 0.28
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
