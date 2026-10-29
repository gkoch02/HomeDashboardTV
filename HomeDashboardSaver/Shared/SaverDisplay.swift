import AppKit

/// A display as the saver's per-display layouts know it. System Settings lets each display run
/// its own screensaver but never tells a saver's Options which display it is configuring, so
/// Options lists every connected display, and each saver view looks up the display it is on.
///
/// A display is keyed by its vendor, model and serial, which stay the same across reconnects
/// and restarts, unlike its `CGDirectDisplayID`.
enum SaverDisplay {
    /// The defaults key: a dictionary from display key to a layout's raw value. A display
    /// without an entry shows the shared `layout`.
    static let layoutsKey = "displayLayouts"

    static func key(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        let id = CGDirectDisplayID(number.uint32Value)
        return "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
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
}
