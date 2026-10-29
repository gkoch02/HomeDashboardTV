import DashboardCore
import SwiftUI

/// One look for the screen, one entry in the Layout picker.
///
/// A theme draws, and `ThemeFrame` does the rest: the theme's body is the plate, which moves
/// with the burn-in drift; `backdrop` stays put behind it and runs to the screen's edge, so the
/// drift never uncovers one; the notice sits still in the top-right corner over both, in the
/// theme's own style. The frame also sets the snapshot's zone as `\.timeZone`.
///
/// The plate keeps inside tvOS's overscan safe area unless the theme sets `fullBleed`; then it
/// gets the whole screen and keeps its own margin, at least 10 pt for the drift.
///
/// To add one: conform a view, add a case to `DashboardStore.Layout`, and a line to
/// `LayoutSwitch`. Shared pieces (the weather painting, the moon disc, a starfield)
/// are in `Parts/`; keep the theme's own inks and faces `private` to its file.
protocol Theme: View {
    associatedtype Backdrop: View
    associatedtype Notice: View = NoticeCapsule

    init(snapshot: Snapshot, now: Date)

    /// The plate runs to the screen's edge instead of keeping inside the safe area.
    static var fullBleed: Bool { get }
    var snapshot: Snapshot { get }
    @ViewBuilder var backdrop: Backdrop { get }
    /// The corner line: the connection is down, or a source has gone stale.
    @ViewBuilder func notice(_ text: String) -> Notice
}

extension Theme {
    static var fullBleed: Bool { false }
}

extension Theme where Notice == NoticeCapsule {
    func notice(_ text: String) -> NoticeCapsule { NoticeCapsule(text: text) }
}

/// Composes a theme: still backdrop, drifting plate, still notice.
struct ThemeFrame<T: Theme>: View {
    let theme: T
    let now: Date
    let notice: String?

    // The drift goes on before the safe area is ignored: offsetting a view that already
    // ignores it moved the plate in by the safe area's insets.
    var body: some View {
        theme
            .offset(BurnIn.drift(at: now))
            .ignoresSafeArea(edges: T.fullBleed ? .all : [])
            .background { theme.backdrop.ignoresSafeArea() }
            .overlay {
                if let notice {
                    Color.clear
                        .overlay(alignment: .topTrailing) {
                            theme.notice(notice)
                                .padding(.top, 36)
                                .padding(.trailing, 56)
                        }
                        .ignoresSafeArea()
                }
            }
            .environment(\.timeZone, theme.snapshot.timeZone)
    }
}

/// The layout for a `DashboardStore.Layout`, framed. The TV's `DashboardScreen` and the Mac
/// screensaver's `SaverScreen` both put this inside the screen they own.
struct LayoutSwitch: View {
    let layout: DashboardStore.Layout
    let snapshot: Snapshot
    let now: Date
    let notice: String?

    var body: some View {
        switch layout {
        case .dashboard: frame(DashboardView.self)
        case .agenda: frame(AgendaPlateView.self)
        case .moon: frame(MoonView.self)
        case .horizon: frame(HorizonView.self)
        case .light: frame(LightCycleView.self)
        case .quote: frame(QuoteView.self)
        case .night: frame(NightView.self)
        case .skylight: frame(SkylightView.self)
        case .fuzzy: frame(FuzzyClockView.self)
        case .weatherglass: frame(WeatherglassView.self)
        case .aurora: frame(AuroraView.self)
        case .orrery: frame(OrreryView.self)
        case .window: frame(WindowView.self)
        case .cyberpunk: frame(CyberpunkView.self)
        case .uplink: frame(UplinkView.self)
        case .steward: frame(StewardView.self)
        case .wing: frame(StewardWingView.self)
        case .grimoire: frame(GrimoireView.self)
        }
    }

    private func frame<T: Theme>(_ theme: T.Type) -> some View {
        ThemeFrame(theme: T(snapshot: snapshot, now: now), now: now, notice: notice)
    }
}

extension EnvironmentValues {
    /// The side of this screen another display sits on, for the layouts made as a pair
    /// (Steward and its wing); nil with none beside it, as on the TV. The Mac saver sets it from
    /// the displays' arrangement.
    @Entry var partnerEdge: HorizontalEdge? = nil
}

/// Moves the plate a few points every ten minutes, so an OLED set never holds one image.
/// Themes keep a 10 pt margin clear of the edge for it.
enum BurnIn {
    /// Up to 10 points in each axis, a new spot every ten minutes.
    static func drift(at now: Date) -> CGSize {
        let slot = Int(now.timeIntervalSince1970 / 600)
        let x = Double((slot * 7) % 21) - 10
        let y = Double((slot * 13) % 21) - 10
        return CGSize(width: x, height: y)
    }
}

/// The default notice: an amber line on a dark capsule.
struct NoticeCapsule: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.arrow.circlepath")
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(Color.p3(1.0, 0.78, 0.30))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.black.opacity(0.45), in: Capsule())
    }
}
