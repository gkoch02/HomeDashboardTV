import DashboardCore
import SwiftUI

/// Settings as a drawer at the screen's trailing edge, built as IdleHoursTV's settings panel
/// is: each page a stack of uniform full-width rows, on a material panel flush with the edge.
/// The root holds the layout, Keep Awake and where the dashboard comes from (a Pi found on
/// the network, a typed address, or the bundled demo week), with the web UI's login; each
/// choice opens a page of its own. Menu goes back a page, then closes the drawer once there
/// is a source to show. The dashboard stays visible beside it, so a layout picked here shows
/// at once.
///
/// No `List` or `NavigationStack`: their scroll and navigation views clipped the focused
/// row's lifted pill at both ends on the TV, which the simulator never showed. Plain rows in
/// a padded stack leave the lift room inside the panel; the Layout list, too long for the
/// panel, scrolls in a `ScrollView` with its clip swapped for a mask, as IdleHoursTV's is.
struct SettingsView: View {
    @Environment(DashboardStore.self) private var store
    @State private var browser = PiBrowser()
    @State private var typedAddress = ""
    @State private var resolving: String?
    @State private var addressError: String?
    @State private var page: Page = .root
    /// The row last focused on each page, so stepping back lands where you left.
    @State private var lastFocused: [Page: String] = [:]
    @FocusState private var focused: String?

    enum Page { case root, layout, keepAwake, highlights, source }

    static let width: CGFloat = 780

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch page {
            case .root: rootPage
            case .layout: layoutPage
            case .keepAwake: keepAwakePage
            case .highlights: highlightsPage
            case .source: sourcePage
            }
        }
        // Inside tvOS's safe margins on the outer edge (90 across, 60 down), and 48 on the
        // inner edge: room for a focused row to grow without leaving the panel.
        .padding(.leading, 48)
        .padding(.trailing, 90)
        .padding(.vertical, 60)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
        // Always a dark panel with light text, whatever the layout behind it.
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .ignoresSafeArea()
        .onAppear {
            browser.start()
            if case let .server(url) = store.connection { typedAddress = url.host().map { "\($0):\(url.port ?? 8080)" } ?? "" }
            // A first launch has nothing to show yet: straight to choosing a source.
            if store.connection == nil { page = .source }
            enter()
        }
        // Browsing the drawer is remote use too, so it restarts Keep awake: a move, a page
        // opened, a keystroke.
        .onChange(of: page) { _, _ in
            store.noteInteraction()
            enter()
        }
        .onChange(of: focused) { _, id in
            store.noteInteraction()
            if let id { lastFocused[page] = id }
        }
        .onChange(of: typedAddress) { _, _ in store.noteInteraction() }
        .onChange(of: store.username) { _, _ in store.noteInteraction() }
        .onChange(of: store.password) { _, _ in store.noteInteraction() }
        .onChange(of: browser.found) { _, found in
            // The first Pi to turn up is the likeliest choice on a first launch.
            if store.connection == nil, page == .source, let first = found.first {
                focused = "pi-\(first.name)"
            }
        }
        .onDisappear { browser.stop() }
        .onExitCommand {
            store.noteInteraction()
            if page != .root {
                page = .root
            } else if store.connection != nil {
                store.settingsVisible = false
            }
        }
    }

    // MARK: Pages

    private var rootPage: some View {
        @Bindable var store = store
        return Group {
            title("Home Dashboard")
            footnote(status)
                .padding(.bottom, 8)
            row(id: "layout", title: "Layout", value: store.layout.title, chevron: true) { page = .layout }
            row(id: "awake", title: "Keep Awake", detail: "Holds off the screensaver and sleep",
                value: awakeLabel(store.keepAwakeHours), chevron: true) { page = .keepAwake }
            row(id: "highlights", title: "Highlights", detail: "Skies brighter than white on an HDR output",
                value: store.highlights.title, chevron: true) { page = .highlights }
            row(id: "source", title: "Source", value: sourceName, chevron: true) { page = .source }
            sectionHeader("Web UI login, if the Pi has a password")
            TextField("Username", text: $store.username)
                .focused($focused, equals: "username")
            SecureField("Password", text: $store.password)
                .focused($focused, equals: "password")
            Spacer(minLength: 0)
            footnote("Left and right on the remote step through the layouts. Menu closes this panel.")
        }
    }

    private var layoutPage: some View {
        Group {
            title("Layout")
            footnote("Menu goes back.")
            // More layouts than fit the panel's height: the list scrolls, as IdleHoursTV's
            // theme list does.
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(DashboardStore.Layout.allCases, id: \.self) { layout in
                        row(id: "layout-\(layout.rawValue)", title: layout.title, value: tick(store.layout == layout)) {
                            store.layout = layout
                            page = .root
                        }
                    }
                }
                // Room for the focused row to grow at the top, and for the last row to
                // scroll clear of the bottom fade.
                .padding(.top, 16)
                .padding(.bottom, ScrollFade.bottom + 16)
            }
            .scrollRunsToBottom()
        }
    }

    private var keepAwakePage: some View {
        Group {
            title("Keep Awake")
            ForEach(DashboardStore.keepAwakeChoices, id: \.self) { hours in
                row(id: "awake-\(hours)", title: awakeLabel(hours), value: tick(store.keepAwakeHours == hours)) {
                    store.keepAwakeHours = hours
                    page = .root
                }
            }
            Spacer(minLength: 0)
            footnote("For that long after a remote press, the Apple TV neither starts its screensaver nor goes to sleep. After that its own timers take over: the screensaver, then sleep. Menu goes back.")
        }
    }

    private var highlightsPage: some View {
        Group {
            title("Highlights")
            ForEach(DashboardStore.Highlights.allCases, id: \.self) { choice in
                row(id: "highlights-\(choice.rawValue)", title: choice.title, value: tick(store.highlights == choice)) {
                    store.highlights = choice
                    page = .root
                }
            }
            Spacer(minLength: 0)
            footnote("Skylight, Aurora and Window can draw their brightest things, the sun, lightning, the aurora's folds and the lights beyond the glass, brighter than the text's white when the Apple TV's Format is an HDR or Dolby Vision mode. Automatic turns that on once the screen reports the range; HDR turns it on regardless, for a Format the screen never reports (in an SDR Format those things clip to white); SDR keeps everything within white. Menu goes back.")
        }
    }

    private var sourcePage: some View {
        Group {
            title("Source")
            sectionHeader("On this network")
            if browser.found.isEmpty {
                HStack(spacing: 18) {
                    ProgressView()
                    footnote("Looking for dashboards… A Pi appears here once `make web-enable` has run on it.")
                }
                .padding(.horizontal, 12)
            }
            ForEach(browser.found) { found in
                row(id: "pi-\(found.name)", title: found.name,
                    value: resolving == found.name ? "Connecting…" : nil) {
                    Task { await choose(found) }
                }
            }
            sectionHeader("By address")
            TextField("dashboard.local:8080", text: $typedAddress)
                .textContentType(.URL)
                .onSubmit(connectTyped)
                .focused($focused, equals: "address")
            row(id: "connect", title: "Connect", action: connectTyped)
            if let addressError {
                Text(addressError)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
            }
            sectionHeader("Or")
            row(id: "demo", title: "Demo data", detail: "A built-in week, with no Pi at all",
                value: tick(store.connection == .demo)) {
                store.connect(.demo)
                store.settingsVisible = false
            }
            Spacer(minLength: 0)
            footnote(store.connection == nil ? "Choose where the dashboard comes from." : "Menu goes back.")
        }
    }

    /// Focus as a page opens: where it was last left, else the current choice, else the
    /// page's first row.
    private func enter() {
        let target: String
        if let last = lastFocused[page] {
            target = last
        } else {
            switch page {
            case .root: target = "layout"
            case .layout: target = "layout-\(store.layout.rawValue)"
            case .keepAwake: target = "awake-\(store.keepAwakeHours)"
            case .highlights: target = "highlights-\(store.highlights.rawValue)"
            case .source: target = browser.found.first.map { "pi-\($0.name)" } ?? "address"
            }
        }
        // A turn later, once the page's rows exist to take it.
        DispatchQueue.main.async { focused = target }
    }

    // MARK: Pieces

    private func title(_ s: String) -> some View {
        Text(s).font(.title2.weight(.semibold)).padding(.bottom, 6)
    }

    private func sectionHeader(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 14)
            .padding(.horizontal, 12)
    }

    private func footnote(_ s: String) -> some View {
        Text(LocalizedStringKey(s)).font(.footnote).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// One uniform row: a title on the left, an optional detail under it, a value or a
    /// chevron on the right. Every row takes the full width at the same height.
    private func row(id: String, title: String, detail: String? = nil, value: String? = nil,
                     chevron: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    // Leading, not the button's centred default, when a long name wraps.
                    Text(title).font(.headline)
                        .multilineTextAlignment(.leading)
                    if let detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                if let value { Text(value).font(.headline).foregroundStyle(.secondary) }
                if chevron { Image(systemName: "chevron.right").font(.headline).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        }
        .focused($focused, equals: id)
    }

    private func tick(_ on: Bool) -> String? { on ? "✓" : nil }

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
    /// A long list runs on past the panel's bottom margin to the screen's edge and fades
    /// out there, as in IdleHoursTV and the system Settings app, rather than stopping at a
    /// hard line with a row cut in half.
    func scrollRunsToBottom() -> some View {
        self
            // The scroll view's own clip cut the rounded ends off the rows, the focused one
            // most, since tvOS scales it up. The mask clips top and bottom instead, and
            // reaches well past the sides so it never touches the ends.
            .scrollClipDisabled()
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: ScrollFade.top)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: ScrollFade.bottom)
                }
                .padding(.horizontal, -80)
            }
            // After the mask, so the mask spans the extended viewport into the panel's
            // bottom margin; before it, the last row could not clear the fade.
            .padding(.bottom, -60)
    }
}

/// Heights of the list fades. The list's bottom content inset is derived from `bottom` so
/// the last row always scrolls fully clear of it.
private enum ScrollFade {
    static let top: CGFloat = 16
    static let bottom: CGFloat = 160
}
