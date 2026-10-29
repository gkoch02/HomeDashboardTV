import DashboardCore
import SwiftUI

/// The dashboard as the screensaver and its host window show it: `DashboardScreen` without the
/// remote and the settings drawer.
///
/// The layouts are drawn for a 1920×1080-point TV, so the screen is laid out at that scale
/// (as wide or as tall as the display's shape needs, the other side 1920 or 1080) and scaled
/// to fit, with tvOS's overscan margins as its safe area: a layout that keeps inside it on the
/// TV keeps inside it here, and a full-bleed one runs to the edge. A display bigger than the
/// TV gets the layouts at 1:1 on a bigger canvas instead of scaled up: `scaleEffect` enlarges
/// text as a bitmap, which blurs it.
///
/// With `rotateMinutes` set, the layouts take turns in the settings list's order, each for
/// that long, with the TV's fade through black between them.
struct SaverScreen: View {
    let store: DashboardStore
    var rotateMinutes = 0
    @State private var layout: DashboardStore.Layout?
    @State private var shown: CGFloat = 1

    /// The TV's screen in points, and its overscan safe area.
    static let tv = CGSize(width: 1920, height: 1080)
    static let overscan = EdgeInsets(top: 60, leading: 80, bottom: 60, trailing: 80)

    var body: some View {
        GeometryReader { screen in
            let scale = min(screen.size.width / Self.tv.width, screen.size.height / Self.tv.height, 1)
            let canvas = CGSize(width: screen.size.width / max(scale, 0.01), height: screen.size.height / max(scale, 0.01))
            content
                .safeAreaPadding(Self.overscan)
                .frame(width: canvas.width, height: canvas.height)
                .environment(store)
                .environment(\.colorScheme, .dark)
                .scaleEffect(scale)
                .frame(width: screen.size.width, height: screen.size.height)
        }
        .background(Color.black)
        .ignoresSafeArea()
        .task(id: rotateMinutes) { await rotate() }
    }

    private var content: some View {
        TimelineView(.everyMinute) { context in
            if let snapshot = store.snapshot {
                let layout = layout ?? store.layout
                LayoutSwitch(layout: layout, snapshot: snapshot, now: context.date, notice: store.notice)
                    .id(layout)
                    .opacity(shown)
                    .background { Color.black.ignoresSafeArea() }
            } else if store.connection == nil {
                Waiting(problem: "No dashboard chosen yet.", hint: "Choose one under Options in the Screen Saver settings.")
            } else {
                Waiting(problem: store.problem, hint: "Check the address under Options in the Screen Saver settings.")
            }
        }
    }

    /// Steps to the next layout every `rotateMinutes` through black, as the remote does on the
    /// TV: out, change while dark, in.
    private func rotate() async {
        guard rotateMinutes > 0 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(rotateMinutes * 60))
            guard !Task.isCancelled else { return }
            let next = (layout ?? store.layout).advanced(by: 1)
            withAnimation(.easeIn(duration: 0.28)) {
                shown = 0
            } completion: {
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) { layout = next }
                withAnimation(.easeOut(duration: 0.28)) { shown = 1 }
            }
        }
    }
}
