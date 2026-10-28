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
                // The animations belong to the scrim and the drawer alone: one on the whole
                // screen also animated whatever the layout behind re-laid out in that update.
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                SettingsView()
                    .transition(.move(edge: .trailing).combined(with: .opacity)
                        .animation(.spring(response: 0.42, dampingFraction: 0.9)))
            }
        }
        .background(Color(red: 0.05, green: 0.06, blue: 0.09))
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
                    LayoutSwitch(layout: store.layout, snapshot: snapshot, now: context.date,
                                 notice: store.notice)
                        .id(store.layout)
                        .opacity(shown)
                        .background { Color.black.ignoresSafeArea() }
                } else if store.connection != nil {
                    Waiting(problem: store.problem, hint: "Click to change where the dashboard comes from.")
                }
            }
    }
}

/// Moving between layouts with the remote: a fade through black. Driven by one animated
/// opacity on the layout, not by SwiftUI transitions, whose implicit animation also animated
/// each layout's insides as it was laid out.
private enum FadeThroughBlack {
    /// Each half: out to black, then in from it.
    static let half = 0.28
}
