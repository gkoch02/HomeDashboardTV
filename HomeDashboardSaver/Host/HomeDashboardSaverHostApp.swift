import AppKit
import SwiftUI

/// A window around the saver's screen, for working on the Mac port without locking the
/// screen. It reads the app's standard defaults, so the TV app's launch arguments work
/// (`-layout <id>`, `-demo YES`, `-server <address>`, `-highlights`). Left and right arrows step
/// through the layouts. `-snapshot <path> [-settle <s>]` captures the window after the
/// build-ins have played and quits, for screenshots and visual checks; `-window WxH` sizes the
/// window (default 1280×720), for a look at a 16:10 display or the System Settings preview's
/// scale. `-showOptions YES` opens the saver's Options sheet as a window beside it (and
/// `-snapshot` captures that instead), to check the sheet sizes to its rows.
@main
struct HomeDashboardSaverHostApp: App {
    @State private var store: DashboardStore

    static let windowSize: CGSize = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-window"), i + 1 < args.count else { return CGSize(width: 1280, height: 720) }
        let parts = args[i + 1].split(separator: "x").compactMap { Double($0) }
        return parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : CGSize(width: 1280, height: 720)
    }()

    init() {
        PlatformBundle.resources = .main
        PlatformBundle.registerFonts()
        _store = State(initialValue: DashboardStore())
    }

    var body: some Scene {
        WindowGroup("Home Dashboard") {
            HostRoot(store: store)
                .frame(minWidth: 320, minHeight: 180)
        }
        .defaultSize(width: Self.windowSize.width, height: Self.windowSize.height)
        .windowResizability(.contentSize)
        Settings {
            // A fresh store for the new choices, as the saver builds one per session.
            SaverSettingsView(defaults: .standard, onChange: { reload() })
                .padding()
        }
    }

    private func reload() {
        store.stop()
        store = DashboardStore()
        store.start()
    }
}

struct HostRoot: View {
    let store: DashboardStore
    /// `-showOptions`: the Options sheet, kept while it is up.
    @MainActor static var options: SaverConfigureSheet?

    var body: some View {
        SaverScreen(store: store, rotateMinutes: UserDefaults.standard.integer(forKey: "rotateMinutes"))
            .id(ObjectIdentifier(store))
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.leftArrow) { store.layout = store.layout.advanced(by: -1); return .handled }
            .onKeyPress(.rightArrow) { store.layout = store.layout.advanced(by: 1); return .handled }
            .onAppear { store.start() }
            .task {
                // `-window WxH`: the saved frame wins over `defaultSize` on every launch but the
                // first, so the window is sized here.
                if let window = NSApp.windows.first(where: { $0.isVisible }), CommandLine.arguments.contains("-window") {
                    window.setContentSize(HomeDashboardSaverHostApp.windowSize)
                }
                if UserDefaults.standard.bool(forKey: "showOptions") {
                    let sheet = SaverConfigureSheet(defaults: .standard)
                    HostRoot.options = sheet
                    sheet.window.center()
                    sheet.window.makeKeyAndOrderFront(nil)
                }
                guard let snapshot = WindowSnapshot(arguments: CommandLine.arguments) else { return }
                try? await Task.sleep(for: .seconds(snapshot.settle))
                snapshot.write()
                exit(0)
            }
    }
}

/// `-snapshot <path>`: the window's picture after `-settle` seconds (default 16, long
/// enough for every build-in), written as PNG. Captures our own window through the window
/// server, so shaders and timelines come out as drawn.
struct WindowSnapshot {
    let path: String
    let settle: Double

    init?(arguments: [String]) {
        guard let i = arguments.firstIndex(of: "-snapshot"), i + 1 < arguments.count else { return nil }
        path = arguments[i + 1]
        if let j = arguments.firstIndex(of: "-settle"), j + 1 < arguments.count, let s = Double(arguments[j + 1]) {
            settle = s
        } else {
            settle = 16
        }
    }

    /// Whether every sampled pixel is the same colour: the window server's answer for a
    /// window it has not composited.
    private static func isBlank(_ image: CGImage) -> Bool {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return true }
        let rowBytes = image.bytesPerRow, bpp = image.bitsPerPixel / 8
        var first: [UInt8]?
        for y in stride(from: 0, to: image.height, by: max(1, image.height / 16)) {
            for x in stride(from: 0, to: image.width, by: max(1, image.width / 16)) {
                let p = y * rowBytes + x * bpp
                let px = Array(UnsafeBufferPointer(start: bytes + p, count: bpp))
                if first == nil { first = px } else if px != first { return false }
            }
        }
        return true
    }

    @MainActor
    func write() {
        guard let window = HostRoot.options?.window ?? NSApp.windows.first(where: { $0.isVisible }),
              let content = window.contentView else {
            FileHandle.standardError.write("no window to capture\n".data(using: .utf8)!)
            exit(1)
        }
        // The window server's picture has the Metal layers in it, but comes back blank when
        // the screen is locked or capture is not allowed; then the view draws itself, which
        // covers everything but a shader.
        var rep: NSBitmapImageRep?
        if let grabbed = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]),
           !Self.isBlank(grabbed) {
            rep = NSBitmapImageRep(cgImage: grabbed)
        } else if let cached = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: cached)
            rep = cached
            FileHandle.standardError.write("window capture was blank; drew the view instead\n".data(using: .utf8)!)
        }
        guard let rep else { exit(1) }
        guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
        do {
            try png.write(to: URL(fileURLWithPath: path))
        } catch {
            FileHandle.standardError.write("\(error)\n".data(using: .utf8)!)
            exit(1)
        }
    }
}
