import ScreenSaver
import SwiftUI

/// The bundle's principal class. Each screensaver session (and the System Settings preview)
/// gets a fresh `DashboardStore` and SwiftUI tree on `startAnimation` and loses them on
/// `stopAnimation`: the legacy screensaver host keeps the view alive between sessions, and a
/// sky left running in it would go on drawing to nothing.
///
/// The host runs one of these per display in one process, and they share one store, built by
/// the first to start and stopped with the last: one poll of the Pi however many displays.
@objc(HomeDashboardSaverView)
final class HomeDashboardSaverView: ScreenSaverView {
    private static let defaults: UserDefaults = {
        let module = Bundle(for: HomeDashboardSaverView.self).bundleIdentifier ?? "dev.plumpbug.homedashboard.saver"
        return ScreenSaverDefaults(forModuleWithName: module) ?? .standard
    }()

    /// Point the layouts at this bundle and register its faces, once per process.
    private static let prepared: Void = {
        PlatformBundle.resources = Bundle(for: HomeDashboardSaverView.self)
        PlatformBundle.registerFonts()
    }()

    /// The store every display in this process shows, and how many are showing it.
    private static var shared: DashboardStore?
    private static var showing = 0

    private var host: NSView?
    private var sheet: SaverConfigureSheet?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        _ = Self.prepared
        wantsLayer = true
        // The store keeps its own clock and the skies their own frames; nothing to do per frame.
        animationTimeInterval = 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("HomeDashboardSaverView is created in code")
    }

    override func startAnimation() {
        if host == nil {
            // Another process (System Settings' Options) may have written the choices since.
            Self.defaults.synchronize()
            Self.shared?.reloadChoices()
            let store = Self.shared ?? DashboardStore(defaults: Self.defaults)
            let rotate = Self.defaults.integer(forKey: "rotateMinutes")
            let host = NSHostingView(rootView: SaverScreen(store: store, rotateMinutes: rotate))
            host.frame = bounds
            host.autoresizingMask = [.width, .height]
            addSubview(host)
            self.host = host
            Self.showing += 1
            if Self.shared == nil {
                Self.shared = store
                store.start()
            }
        }
        super.startAnimation()
    }

    override func stopAnimation() {
        if host != nil {
            host?.removeFromSuperview()
            host = nil
            Self.showing -= 1
            if Self.showing == 0 {
                Self.shared?.stop()
                Self.shared = nil
            }
        }
        super.stopAnimation()
    }

    override func animateOneFrame() {}

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        if sheet == nil {
            sheet = SaverConfigureSheet(defaults: Self.defaults, onChange: { Self.shared?.reloadChoices() })
        }
        return sheet?.window
    }
}
