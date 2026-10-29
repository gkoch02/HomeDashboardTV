import DashboardCore
import SwiftUI

/// The saver's choices, the TV drawer's as one form: where the dashboard comes from (a Pi
/// found on the network, a typed address, or the demo week), the layout and any display's own
/// (`SaverDisplay`), whether the layouts take turns, and the skies' highlights. It writes the
/// keys `DashboardStore` reads, so the
/// saver's next `startAnimation`, which builds a fresh store, picks them up; the host app's
/// Settings window reloads its store through `onChange`.
///
/// No web UI login: the TV keeps the password in its Keychain, and the screensaver host's
/// Keychain is not one to keep it in.
struct SaverSettingsView: View {
    private let defaults: UserDefaults
    var onChange: () -> Void = {}
    /// The configure sheet's Done button; the host's Settings window has none.
    var done: (() -> Void)?

    @State private var browser = PiBrowser()
    @State private var demo: Bool
    @State private var address: String
    @State private var layout: DashboardStore.Layout
    /// The connected displays, by key and name, when there is more than one, or when the one
    /// left still has a layout of its own, so it can be put back.
    private let displays: [(key: String, name: String)]
    @State private var displayLayouts: [String: String]
    @State private var rotateMinutes: Int
    @State private var highlights: DashboardStore.Highlights
    @State private var resolving: String?
    @State private var addressError: String?

    static let rotateChoices = [0, 5, 15, 30, 60]

    init(defaults: UserDefaults, onChange: @escaping () -> Void = {}, done: (() -> Void)? = nil) {
        self.defaults = defaults
        self.onChange = onChange
        self.done = done
        let saved = defaults.string(forKey: "connection")
        _demo = State(initialValue: saved == "demo")
        let url = saved.flatMap(URL.init(string:)).flatMap { $0.host() == nil ? nil : $0 }
        _address = State(initialValue: url.map(Self.typed) ?? "")
        _layout = State(initialValue: defaults.string(forKey: "layout").flatMap(DashboardStore.Layout.init(saved:)) ?? .dashboard)
        let screens = NSScreen.screens.compactMap { s in SaverDisplay.key(for: s).map { (key: $0, name: s.localizedName) } }
        let displayLayouts = SaverDisplay.layouts(in: defaults)
        displays = screens.count > 1 || screens.contains { displayLayouts[$0.key] != nil } ? screens : []
        _displayLayouts = State(initialValue: displayLayouts)
        _rotateMinutes = State(initialValue: defaults.integer(forKey: "rotateMinutes"))
        _highlights = State(initialValue: defaults.string(forKey: "highlights").flatMap(DashboardStore.Highlights.init(rawValue:)) ?? .automatic)
    }

    var body: some View {
        Form {
            Section("Source") {
                Picker("Source", selection: $demo) {
                    Text("A dashboard Pi").tag(false)
                    Text("Demo data").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if !demo {
                    TextField("Address", text: $address, prompt: Text("dashboard.local:8080"))
                        .onSubmit(saveAddress)
                    if let addressError {
                        Text(addressError).foregroundStyle(.red)
                    }
                    if browser.found.isEmpty {
                        Text("Looking for dashboards on this network… A Pi appears here once `make web-enable` has run on it.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(browser.found) { found in
                        HStack {
                            Text(found.name)
                            Spacer()
                            if resolving == found.name {
                                ProgressView().controlSize(.small)
                            } else {
                                Button("Use") { Task { await choose(found) } }
                            }
                        }
                    }
                }
            }
            Section {
                Picker("Layout", selection: $layout) {
                    ForEach(DashboardStore.Layout.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Change layout", selection: $rotateMinutes) {
                    ForEach(Self.rotateChoices, id: \.self) { Text(rotateLabel($0)).tag($0) }
                }
                Picker("Highlights", selection: $highlights) {
                    ForEach(DashboardStore.Highlights.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } footer: {
                Text("Highlights: Skylight, Aurora and Window can draw the sun, lightning and the lights beyond the glass brighter than white on an XDR or HDR display. Automatic does so where the display can.")
                    .foregroundStyle(.secondary)
            }
            if !displays.isEmpty {
                Section {
                    ForEach(displays, id: \.key) { display in
                        Picker(display.name, selection: displayLayout(display.key)) {
                            Text("Same as Layout").tag(DashboardStore.Layout?.none)
                            Divider()
                            ForEach(DashboardStore.Layout.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                        }
                    }
                } header: {
                    Text("Displays")
                } footer: {
                    Text("A display can show a layout of its own; one left on Same as Layout shows the one above.")
                        .foregroundStyle(.secondary)
                }
            }
            if let done {
                HStack {
                    Spacer()
                    Button("Done") {
                        saveAddress()
                        done()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .formStyle(.grouped)
        // A grouped Form scrolls and has no height of its own; held still, it is as tall as
        // its rows, which is what the configure sheet sizes its window from.
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 480)
        .onAppear { browser.start() }
        .onDisappear { browser.stop() }
        .onChange(of: demo) { _, demo in
            if demo { save("demo", "connection") } else { saveAddress() }
        }
        .onChange(of: layout) { _, layout in save(layout.rawValue, "layout") }
        .onChange(of: rotateMinutes) { _, minutes in save(minutes, "rotateMinutes") }
        .onChange(of: highlights) { _, highlights in save(highlights.rawValue, "highlights") }
    }

    /// A saved URL as the field shows it: `host:port` for a plain HTTP root, which
    /// `DashboardClient.baseURL(forTyped:)` turns back into the same URL, else the whole URL, so
    /// opening Options and pressing Done never rewrites an HTTPS or sub-path address.
    static func typed(_ url: URL) -> String {
        guard url.scheme == "http", url.path == "/" || url.path.isEmpty, url.query == nil,
              let host = url.host() else { return url.absoluteString }
        return "\(host):\(url.port ?? 8080)"
    }

    /// A display's own layout, nil to follow the shared one; set, it saves the lot.
    private func displayLayout(_ key: String) -> Binding<DashboardStore.Layout?> {
        Binding {
            displayLayouts[key].flatMap(DashboardStore.Layout.init(saved:))
        } set: { layout in
            displayLayouts[key] = layout?.rawValue
            save(displayLayouts, SaverDisplay.layoutsKey)
        }
    }

    private func rotateLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: return "Never"
        case 60: return "Every hour"
        default: return "Every \(minutes) minutes"
        }
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        defaults.synchronize()
        onChange()
    }

    /// The typed address as the connection, if it reads as one; an empty field leaves the
    /// saved one alone.
    private func saveAddress() {
        guard !demo, !address.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let url = DashboardClient.baseURL(forTyped: address) else {
            addressError = "That doesn't look like an address."
            return
        }
        addressError = nil
        if defaults.string(forKey: "connection") != url.absoluteString { save(url.absoluteString, "connection") }
    }

    private func choose(_ found: PiBrowser.Found) async {
        resolving = found.name
        defer { resolving = nil }
        guard let url = await PiBrowser.resolve(found.endpoint) else {
            addressError = "Couldn't reach \(found.name)."
            return
        }
        address = Self.typed(url)
        saveAddress()
    }
}
