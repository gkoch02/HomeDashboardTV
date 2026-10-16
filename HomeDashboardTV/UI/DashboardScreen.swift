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
    /// The slide between layouts: the layout leaving, which way the press went (-1 left,
    /// 1 right), and how far along it is, 0 to 1. Only `progress` animates.
    @State private var leaving: DashboardStore.Layout?
    @State private var direction: CGFloat = 0
    @State private var progress: CGFloat = 1
    /// Counts slides, so one cut short by the next press does not clear the next one's
    /// leaving layout when its own animation finishes.
    @State private var slide = 0

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

    /// Steps the layout and slides to it. Everything about the slide is set in this one
    /// update, so the leaving layout and the arriving one always agree on the direction; a
    /// press during a slide starts the next from where the screen now stands.
    private func change(by steps: Int) {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            leaving = store.layout
            direction = CGFloat(steps.signum())
            progress = 0
            store.layout = store.layout.advanced(by: steps)
            slide += 1
        }
        let this = slide
        withAnimation(.easeInOut(duration: LayoutSlide.duration)) {
            progress = 1
        } completion: {
            if slide == this { leaving = nil }
        }
    }

    private func claimFocus() {
        guard !store.settingsVisible else { return }
        DispatchQueue.main.async { screenFocused = true }
    }

    private var content: some View {
            TimelineView(.everyMinute) { context in
                if let snapshot = store.snapshot {
                    ZStack {
                        if let leaving, leaving != store.layout {
                            layout(leaving, snapshot, context.date)
                                .id(leaving)
                                .offset(x: -direction * LayoutSlide.travel * progress)
                                .opacity(1 - progress)
                        }
                        layout(store.layout, snapshot, context.date)
                            .id(store.layout)
                            .offset(x: direction * LayoutSlide.travel * (1 - progress))
                            .opacity(leaving == nil ? 1 : progress)
                    }
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

/// Moving between layouts with the remote: the new one drifts in from the side pressed as
/// the old one drifts out the other way, both a fraction of the screen, crossfading as they
/// go. Driven by one animated `progress` on the two layers' offset and opacity alone, not by
/// SwiftUI transitions: an implicit animation also animated each layout's own insides as
/// they were laid out, and a removal transition keeps the direction of the frame before.
private enum LayoutSlide {
    /// How far a layout travels: enough to read as a move, short of a full push.
    static let travel: CGFloat = 220
    static let duration = 0.55
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
