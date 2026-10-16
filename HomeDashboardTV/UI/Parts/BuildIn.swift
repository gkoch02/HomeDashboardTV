import SwiftUI

extension View {
    /// Plays a layout's build-in whenever it appears: at launch, stepped to with the remote, or
    /// picked in settings, once the panel has closed so the build-in is seen. Not on the minute
    /// redraws, which keep the view and its state.
    ///
    /// *reset* puts the layout at the start of its build-in, or at rest when *settled* (under
    /// Reduce Motion), with animations off; *play* runs a turn later, so the start is drawn
    /// before anything animates away from it. Under Reduce Motion *play* never runs.
    func onBuildIn(reset: @escaping (_ settled: Bool) -> Void, play: @escaping () -> Void) -> some View {
        modifier(BuildInTrigger(reset: reset, play: play))
    }

    /// Shows the view up to *progress* (0 to 1) along *edge*'s axis, from that edge, behind a
    /// soft front *softness* of the view's length wide.
    func wipe(_ progress: Double, from edge: Edge = .leading, softness: CGFloat = 0.2) -> some View {
        modifier(Wipe(progress: progress, edge: edge, softness: softness))
    }
}

private struct BuildInTrigger: ViewModifier {
    let reset: (Bool) -> Void
    let play: () -> Void

    /// Appeared under the settings panel: the build-in waits for it to close.
    @State private var pending = false
    @Environment(DashboardStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onAppear {
                if store.settingsVisible {
                    pending = true
                    resetInstantly()
                } else {
                    start()
                }
            }
            .onChange(of: store.settingsVisible) { _, visible in
                if !visible && pending {
                    pending = false
                    start()
                }
            }
    }

    private func resetInstantly() {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { reset(reduceMotion) }
    }

    private func start() {
        resetInstantly()
        guard !reduceMotion else { return }
        DispatchQueue.main.async { play() }
    }
}

/// A mask that slides on: the gradient is the view's length plus its soft front, offset so
/// that only an animatable offset changes as *progress* runs.
private struct Wipe: ViewModifier, Animatable {
    var progress: Double
    let edge: Edge
    let softness: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.mask {
            GeometryReader { geometry in
                let horizontal = edge == .leading || edge == .trailing
                let length = horizontal ? geometry.size.width : geometry.size.height
                let front = length * softness
                let travel = length + front
                let solid = length / travel
                let toward: UnitPoint = switch edge {
                case .leading: .trailing
                case .trailing: .leading
                case .top: .bottom
                case .bottom: .top
                }
                let away = UnitPoint(x: 1 - toward.x, y: 1 - toward.y)
                let shift = (progress - 1) * travel * (edge == .leading || edge == .top ? 1 : -1)
                LinearGradient(stops: [.init(color: .white, location: 0),
                                       .init(color: .white, location: solid),
                                       .init(color: .clear, location: 1)],
                               startPoint: away, endPoint: toward)
                    .frame(width: horizontal ? travel : geometry.size.width,
                           height: horizontal ? geometry.size.height : travel)
                    .offset(x: horizontal ? shift - (edge == .trailing ? front : 0) : 0,
                            y: horizontal ? 0 : shift - (edge == .bottom ? front : 0))
            }
        }
    }
}
