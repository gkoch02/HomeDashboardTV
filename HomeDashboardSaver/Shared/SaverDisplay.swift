import AppKit
import SwiftUI

/// A display as the saver's per-display layouts know it. System Settings lets each display run
/// its own screensaver but never tells a saver's Options which display it is configuring, so
/// Options lists every connected display, and each saver view looks up the display it is on.
///
/// A display is keyed by its vendor, model and serial, which stay the same across reconnects
/// and restarts, unlike its `CGDirectDisplayID`. One that reports no serial (zero) takes its
/// unit number instead, so two such displays of the same model don't share a key.
enum SaverDisplay {
    /// The defaults key: a dictionary from display key to a layout's raw value. A display
    /// without an entry shows the shared `layout`.
    static let layoutsKey = "displayLayouts"

    static func key(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        let id = CGDirectDisplayID(number.uint32Value)
        let serial = CGDisplaySerialNumber(id)
        let last = serial != 0 ? "\(serial)" : "u\(CGDisplayUnitNumber(id))"
        return "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(last)"
    }

    /// Every display's own layout, by display key.
    static func layouts(in defaults: UserDefaults) -> [String: String] {
        defaults.dictionary(forKey: layoutsKey) as? [String: String] ?? [:]
    }

    /// The layout chosen for *screen*, or nil to follow the shared one.
    static func layout(for screen: NSScreen?, in defaults: UserDefaults) -> DashboardStore.Layout? {
        guard let screen, let key = key(for: screen), let saved = layouts(in: defaults)[key] else { return nil }
        return DashboardStore.Layout(saved: saved)
    }

    /// The side of *screen* the nearest other display sits on, for the layouts made as a pair
    /// (`\.partnerEdge`); nil with only the one.
    static func partnerEdge(for screen: NSScreen?) -> HorizontalEdge? {
        guard let screen else { return nil }
        let others = NSScreen.screens.filter { $0 != screen }
        guard let nearest = others.min(by: { abs($0.frame.midX - screen.frame.midX) < abs($1.frame.midX - screen.frame.midX) })
        else { return nil }
        return nearest.frame.midX < screen.frame.midX ? .leading : .trailing
    }
}
