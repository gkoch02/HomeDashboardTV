import DashboardCore
import SwiftUI

/// Settings as a system-style drawer: a material panel at the screen's trailing edge with the
/// layout and Keep awake as system pickers, and where the dashboard comes from (a Pi found on
/// the network, a typed address, or the bundled demo week) a page deeper, with the web UI's
/// login. Menu goes back a page, then closes the drawer once a source is set.
///
/// The dashboard stays visible beside it, so a layout picked here shows at once.
struct SettingsView: View {
    @Environment(DashboardStore.self) private var store
    @State private var browser = PiBrowser()
    @State private var typedAddress = ""
    @State private var resolving: String?
    @State private var addressError: String?
    @State private var path: [Page] = []
    @FocusState private var focus: Field?

    /// The drawer's deeper pages. Layout and Keep Awake are pickers drawn here rather than
    /// SwiftUI's navigation-link `Picker`, whose pushed list came up blank in a drawer narrower
    /// than the screen.
    enum Page: Hashable {
        case layout, keepAwake, source
    }

    /// The rows focus is sent to by name as a page opens.
    enum Field: Hashable {
        case layout, keepAwake, source, firstChoice, firstSource
    }

    static let width: CGFloat = 780

    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $path) {
            List {
                Section {
                    NavigationLink(value: Page.layout) {
                        LabeledContent("Layout", value: store.layout.title)
                    }
                    .focused($focus, equals: .layout)
                    NavigationLink(value: Page.keepAwake) {
                        LabeledContent("Keep Awake", value: awakeLabel(store.keepAwakeHours))
                    }
                    .focused($focus, equals: .keepAwake)
                } header: {
                    header
                } footer: {
                    Text("Keep Awake holds off the screensaver for that long after a remote press; then the Apple TV's own screensaver and sleep timers apply.")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }

                Section {
                    NavigationLink(value: Page.source) {
                        LabeledContent("Source", value: sourceName)
                    }
                    .focused($focus, equals: .source)
                    TextField("Username", text: $store.username)
                    SecureField("Password", text: $store.password)
                } header: {
                    Text("Dashboard")
                } footer: {
                    Text("The username and password are the Pi web UI's, if it has one.")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }
            }
            .drawerUnclipped()
            .navigationDestination(for: Page.self) { page in
                switch page {
                case .layout:
                    choices("Layout", DashboardStore.Layout.allCases, selected: store.layout, title: \.title) {
                        store.layout = $0
                    }
                case .keepAwake:
                    choices("Keep Awake", DashboardStore.keepAwakeChoices, selected: store.keepAwakeHours,
                            title: awakeLabel) {
                        store.keepAwakeHours = $0
                    }
                case .source:
                    sourcePage
                }
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
        .frame(width: Self.width)
        .background(.thickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 40, x: -10)
        .padding(.vertical, 40)
        .padding(.trailing, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .onAppear {
            browser.start()
            if case let .server(url) = store.connection { typedAddress = url.host().map { "\($0):\(url.port ?? 8080)" } ?? "" }
            // A first launch has nothing to show yet: straight to choosing a source.
            if store.connection == nil { path = [.source] }
            // The drawer takes focus as it appears; nothing else will hand it over.
            DispatchQueue.main.async { focus = store.connection == nil ? .firstSource : .layout }
        }
        // Every remote use in the drawer restarts Keep awake, including a keystroke or a pick
        // that leaves focus where it was.
        .onChange(of: focus) { _, _ in store.noteInteraction() }
        .onChange(of: path) { _, _ in store.noteInteraction() }
        .onChange(of: store.layout) { _, _ in store.noteInteraction() }
        .onChange(of: typedAddress) { _, _ in store.noteInteraction() }
        .onChange(of: store.username) { _, _ in store.noteInteraction() }
        .onChange(of: store.password) { _, _ in store.noteInteraction() }
        .onDisappear { browser.stop() }
        .onExitCommand {
            // Menu goes back a page, focus returning to the row that led there; at the root
            // it closes the drawer, once there is a source to show.
            store.noteInteraction()
            if let page = path.popLast() {
                DispatchQueue.main.async { focus = row(for: page) }
            } else if store.connection != nil {
                store.settingsVisible = false
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Home Dashboard")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.primary)
                .textCase(nil)
            Text(status)
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
                .textCase(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 12)
    }

    private func row(for page: Page) -> Field {
        switch page {
        case .layout: return .layout
        case .keepAwake: return .keepAwake
        case .source: return .source
        }
    }

    // MARK: Pickers

    /// A system-style picker page: one row per choice, a checkmark on the current one, and a
    /// pick goes back a page.
    private func choices<T: Hashable>(_ name: String, _ options: [T], selected: T, title: @escaping (T) -> String,
                                      pick: @escaping (T) -> Void) -> some View {
        List {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button {
                    pick(option)
                    if let page = path.popLast() {
                        DispatchQueue.main.async { focus = row(for: page) }
                    }
                } label: {
                    HStack {
                        Text(title(option))
                        Spacer()
                        if option == selected { Image(systemName: "checkmark") }
                    }
                }
                .focused($focus, equals: option == selected ? .firstChoice : nil)
                .accessibilityLabel(title(option))
            }
        }
        .drawerUnclipped()
        .navigationTitle(name)
        .onAppear { DispatchQueue.main.async { focus = .firstChoice } }
    }

    // MARK: Source

    private var sourcePage: some View {
        List {
            Section {
                if browser.found.isEmpty {
                    HStack(spacing: 18) {
                        ProgressView()
                        Text("Looking for dashboards…")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(Array(browser.found.enumerated()), id: \.element.id) { index, found in
                    Button {
                        Task { await choose(found) }
                    } label: {
                        HStack {
                            Label(found.name, systemImage: "dot.radiowaves.left.and.right")
                            Spacer()
                            if resolving == found.name {
                                ProgressView()
                            }
                        }
                    }
                    .focused($focus, equals: index == 0 ? .firstSource : nil)
                }
            } header: {
                Text("On This Network")
            } footer: {
                Text("A Pi advertises itself here once `make web-enable` has run on it.")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
            }

            Section {
                TextField("dashboard.local:8080", text: $typedAddress)
                    .textContentType(.URL)
                    // With no Pi found yet, the address is where a first launch starts.
                    .focused($focus, equals: browser.found.isEmpty ? .firstSource : nil)
                    .onSubmit(connectTyped)
                Button("Connect", action: connectTyped)
                if let addressError {
                    Text(addressError)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("By Address")
            }

            Section {
                Button {
                    store.noteInteraction()
                    store.connect(.demo)
                    store.settingsVisible = false
                } label: {
                    HStack {
                        Text("Demo data")
                        Spacer()
                        if store.connection == .demo { Image(systemName: "checkmark") }
                    }
                }
            } footer: {
                Text("A built-in week, with no Pi at all.")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
            }
        }
        .drawerUnclipped()
        .navigationTitle("Source")
        .onAppear {
            DispatchQueue.main.async { focus = .firstSource }
        }
        .onChange(of: browser.found) { _, found in
            // The first Pi to turn up is the likeliest choice on a first launch.
            if store.connection == nil, !found.isEmpty {
                // The field already holds `.firstSource`: let go, then hand it to the Pi row.
                focus = nil
                DispatchQueue.main.async { focus = .firstSource }
            }
        }
    }

    // MARK: Text

    private var sourceName: String {
        switch store.connection {
        case nil: return "None"
        case .demo: return "Demo data"
        case .server(let url): return url.host() ?? url.absoluteString
        }
    }

    private func awakeLabel(_ hours: Int) -> String {
        switch hours {
        case 0: return "Always"
        case 1: return "1 hour"
        default: return "\(hours) hours"
        }
    }

    private var status: String {
        switch store.connection {
        case nil:
            return "Choose where the dashboard comes from. Click anywhere later to come back here."
        case .demo:
            return "Showing the built-in demo week."
        case .server(let url):
            if let problem = store.problem { return "\(url.host() ?? url.absoluteString): \(problem)" }
            if let last = store.lastSuccess {
                return "\(url.host() ?? url.absoluteString) · updated \(last.formatted(date: .omitted, time: .shortened))"
            }
            return "Connecting to \(url.host() ?? url.absoluteString)…"
        }
    }

    // MARK: Connecting

    private func choose(_ found: PiBrowser.Found) async {
        store.noteInteraction()
        resolving = found.name
        defer { resolving = nil }
        guard let url = await PiBrowser.resolve(found.endpoint) else {
            addressError = "Couldn't reach \(found.name)."
            return
        }
        addressError = nil
        store.connect(.server(url))
        store.settingsVisible = false
    }

    private func connectTyped() {
        store.noteInteraction()
        guard let url = DashboardClient.baseURL(forTyped: typedAddress) else {
            addressError = "That doesn't look like an address."
            return
        }
        addressError = nil
        store.connect(.server(url))
        store.settingsVisible = false
    }
}

private extension View {
    /// A drawer list's scroll view crops whatever leaves its bounds, which cut a focused row's
    /// lifted pill off flat at both ends. The lists are inset from the drawer's edge (and too
    /// short to scroll), so they draw unclipped and only the drawer's rounded edge clips.
    func drawerUnclipped() -> some View {
        scrollClipDisabled()
    }
}
