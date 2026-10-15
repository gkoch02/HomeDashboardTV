import DashboardCore
import SwiftUI

/// Where the dashboard comes from: a Pi found on the network, a typed address, or the bundled
/// demo week. Plus the web UI's username and password, when it has one.
struct SettingsView: View {
    @Environment(DashboardStore.self) private var store
    @State private var browser = PiBrowser()
    @State private var typedAddress = ""
    @State private var resolving: String?
    @State private var addressError: String?
    @FocusState private var focus: Field?

    /// The controls focus can be sent to by name.
    enum Field: Hashable {
        case layout(DashboardStore.Layout), awake(Int), pi(String), address, connect, demo, username, password, done
    }

    var body: some View {
        @Bindable var store = store
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 28) {
                Text("Home Dashboard")
                    .font(.system(size: 48, weight: .bold))
                Text(status)
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)

                Section("Show") {
                    HStack(spacing: 24) {
                        ForEach(DashboardStore.Layout.allCases, id: \.self) { layout in
                            Button {
                                store.noteInteraction()
                                store.layout = layout
                            } label: {
                                Label(layout.title, systemImage: store.layout == layout ? "checkmark.circle.fill" : "circle")
                            }
                            .focused($focus, equals: .layout(layout))
                        }
                    }
                }

                Section("Keep awake") {
                    HStack(spacing: 24) {
                        ForEach(DashboardStore.keepAwakeChoices, id: \.self) { hours in
                            Button {
                                store.keepAwakeHours = hours
                            } label: {
                                Label(awakeLabel(hours), systemImage: store.keepAwakeHours == hours ? "checkmark.circle.fill" : "circle")
                            }
                            .focused($focus, equals: .awake(hours))
                        }
                    }
                    Text("For that long after a remote press; then the Apple TV's own screensaver and sleep timers apply. Set the screensaver's Start After to Never to go straight to sleep.")
                        .font(.system(size: 22))
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.tertiary)
                }

                Section("On this network") {
                    if browser.found.isEmpty {
                        Text("Looking for dashboards… (the Pi advertises itself after `make web-enable`)")
                            .font(.system(size: 24))
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(browser.found) { found in
                        Button {
                            Task { await choose(found) }
                        } label: {
                            Label(resolving == found.name ? "\(found.name) — connecting…" : found.name,
                                  systemImage: "dot.radiowaves.left.and.right")
                        }
                        .focused($focus, equals: .pi(found.name))
                    }
                }

                Section("Or by address") {
                    HStack(spacing: 24) {
                        TextField("dashboard.local:8080", text: $typedAddress)
                            .textContentType(.URL)
                            .frame(width: 640)
                            .focused($focus, equals: .address)
                        Button("Connect") {
                            store.noteInteraction()
                            connectTyped()
                        }
                            .focused($focus, equals: .connect)
                        Button("Demo data") {
                            store.noteInteraction()
                            store.connect(.demo)
                            store.settingsVisible = false
                        }
                        .focused($focus, equals: .demo)
                    }
                    if let addressError {
                        Text(addressError).font(.system(size: 22)).foregroundStyle(.red)
                    }
                }

                Section("Web UI login (if the Pi has a password)") {
                    HStack(spacing: 24) {
                        TextField("Username", text: $store.username)
                            .frame(width: 360)
                            .focused($focus, equals: .username)
                        SecureField("Password", text: $store.password)
                            .frame(width: 360)
                            .focused($focus, equals: .password)
                    }
                }

                Button("Done") {
                    store.noteInteraction()
                    store.settingsVisible = false
                }
                    .disabled(store.connection == nil)
                    .focused($focus, equals: .done)
            }
            .padding(80)
            .frame(maxWidth: 1400, alignment: .leading)
            .focusSection()
        }
        .onAppear {
            browser.start()
            // The panel takes focus as it appears; nothing else will hand it over.
            DispatchQueue.main.async { focus = initialFocus }
            if case let .server(url) = store.connection { typedAddress = url.host().map { "\($0):\(url.port ?? 8080)" } ?? "" }
        }
        .onChange(of: browser.found) { _, found in
            // The first Pi to turn up is the likeliest choice on a first launch.
            if store.connection == nil, focus == nil || focus == .address, let first = found.first {
                focus = .pi(first.name)
            }
        }
        // Every remote use in the panel restarts Keep awake, including a press or keystroke
        // that leaves focus where it was.
        .onChange(of: focus) { _, _ in store.noteInteraction() }
        .onChange(of: typedAddress) { _, _ in store.noteInteraction() }
        .onChange(of: store.username) { _, _ in store.noteInteraction() }
        .onChange(of: store.password) { _, _ in store.noteInteraction() }
        .onDisappear { browser.stop() }
        .onExitCommand {
            store.noteInteraction()
            if store.connection != nil { store.settingsVisible = false }
        }
    }

    /// Where focus lands when the panel opens: Done once a source is set, else the first Pi
    /// found, else the address field.
    private var initialFocus: Field {
        if store.connection != nil { return .done }
        if let first = browser.found.first { return .pi(first.name) }
        return .address
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
        guard let url = DashboardClient.baseURL(forTyped: typedAddress) else {
            addressError = "That doesn't look like an address."
            return
        }
        addressError = nil
        store.connect(.server(url))
        store.settingsVisible = false
    }
}

private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.secondary)
            content
        }
    }
}
