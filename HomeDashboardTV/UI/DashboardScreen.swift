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
    /// Which way the last layout change went: -1 left, 1 right, 0 from settings.
    @State private var step = 0

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
        .onChange(of: store.settingsVisible) { _, visible in
            // A pick in settings crossfades; only the remote's steps slide.
            if visible { step = 0 }
            claimFocus()
        }
    }

    /// Steps the layout, noting the direction a run-loop turn first: the leaving layout takes
    /// its transition from the last frame it was drawn in, so that frame must carry it.
    private func change(by steps: Int) {
        step = steps
        DispatchQueue.main.async { store.layout = store.layout.advanced(by: steps) }
    }

    private func claimFocus() {
        guard !store.settingsVisible else { return }
        DispatchQueue.main.async { screenFocused = true }
    }

    private var content: some View {
            TimelineView(.everyMinute) { context in
                if let snapshot = store.snapshot {
                    ZStack {
                        layout(snapshot, context.date)
                            .id(store.layout)
                            .transition(LayoutSlide.transition(step: step))
                    }
                    .animation(.easeInOut(duration: 0.55), value: store.layout)
                } else if store.connection != nil {
                    Waiting(problem: store.problem)
                }
            }
    }

    @ViewBuilder private func layout(_ snapshot: Snapshot, _ now: Date) -> some View {
                    switch store.layout {
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

/// Moving between layouts with the remote: the new one drifts in from the side pressed as
/// the old one drifts out the other way, both a fraction of the screen, crossfading as they
/// go. A layout picked in settings (no direction) just crossfades.
private struct LayoutSlide: ViewModifier {
    let offset: CGFloat

    func body(content: Content) -> some View {
        content.offset(x: offset)
    }

    /// How far a layout travels: enough to read as a move, short of a full push.
    static let travel: CGFloat = 220

    static func transition(step: Int) -> AnyTransition {
        let d = CGFloat(step.signum())
        return .asymmetric(
            insertion: .modifier(active: LayoutSlide(offset: d * travel), identity: LayoutSlide(offset: 0))
                .combined(with: .opacity),
            removal: .modifier(active: LayoutSlide(offset: -d * travel), identity: LayoutSlide(offset: 0))
                .combined(with: .opacity)
        )
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
