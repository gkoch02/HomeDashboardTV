import AppKit
import SwiftUI

/// The window System Settings opens for the saver's Options button. The host app shows it too,
/// under `-showOptions`, so a snapshot can check its size.
final class SaverConfigureSheet {
    let window: NSWindow

    init(defaults: UserDefaults, onChange: @escaping () -> Void = {}) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 480, height: 200)),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Home Dashboard"
        let view = SaverSettingsView(defaults: defaults, onChange: onChange, done: { [weak window] in
            guard let window else { return }
            if let parent = window.sheetParent {
                parent.endSheet(window)
            } else {
                window.close()
            }
        })
        // The form has a fixed width and the height of its rows, and the window follows its
        // preferred size as Bonjour adds rows; left to a grouped Form's own sizing, the window
        // shrinks to a bare title bar, which System Settings shows as nothing at all (as
        // IdleHoursTV's sheet found).
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = [.preferredContentSize]
        window.contentViewController = controller
        window.setContentSize(controller.view.fittingSize)
        self.window = window
    }
}
