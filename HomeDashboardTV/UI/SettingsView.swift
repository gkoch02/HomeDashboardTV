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
                    }
                }

                Section("Or by address") {
                    HStack(spacing: 24) {
                        TextField("dashboard.local:8080", text: $typedAddress)
                            .textContentType(.URL)
                            .frame(width: 640)
                        Button("Connect") { connectTyped() }
                        Button("Demo data") {
                            store.connect(.demo)
                            store.settingsVisible = false
                        }
                    }
                    if let addressError {
                        Text(addressError).font(.system(size: 22)).foregroundStyle(.red)
                    }
                }

                Section("Web UI login (if the Pi has a password)") {
                    HStack(spacing: 24) {
                        TextField("Username", text: $store.username)
                            .frame(width: 360)
                        SecureField("Password", text: $store.password)
                            .frame(width: 360)
                    }
                }

                Button("Done") { store.settingsVisible = false }
                    .disabled(store.connection == nil)
            }
            .padding(80)
            .frame(maxWidth: 1400, alignment: .leading)
        }
        .onAppear {
            browser.start()
            if case let .server(url) = store.connection { typedAddress = url.host().map { "\($0):\(url.port ?? 8080)" } ?? "" }
        }
        .onDisappear { browser.stop() }
        .onExitCommand {
            if store.connection != nil { store.settingsVisible = false }
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
