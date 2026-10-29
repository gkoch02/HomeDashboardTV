import DashboardCore
import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// Where the snapshot comes from, and the polling loop that keeps it current.
///
/// The Pi refreshes its cache on its own timer, so polling faster than every few minutes
/// only re-reads the same file. The last good snapshot stays on screen through a failure;
/// `problem` says what went wrong and since when.
///
/// The Mac screensaver runs one too, over its own defaults: there is no remote, so no settings
/// panel over the layout and no idle timer to hold, and no web UI login (the password lives in
/// the TV's Keychain).
@MainActor
@Observable
final class DashboardStore {
    /// What the screen shows: the week, everything as Cyberpunk 2077's Journal, the day as a
    /// hologram orbit, the day's agenda plate, the next 72 hours on one axis, the live sky, the
    /// street through a rainy window, today on a 24-hour dial, a deck of weather instruments, a
    /// brass orrery, the time in words, the day's quote, the Pi's moonphase theme, an aurora
    /// coloured by the air, or a night plate.
    /// Each case is a `Theme`, drawn in `DashboardScreen.content`.
    ///
    /// The order is the settings list's and the remote's left and right: the busiest first,
    /// down to the calmest, with Night, the after-dark plate, last. Saved by raw value, so
    /// reordering keeps a saved choice.
    enum Layout: String, CaseIterable {
        case dashboard, cyberpunk, uplink, steward, wing, grimoire, agenda, horizon, skylight, window, light, weatherglass, orrery, fuzzy, quote, moon, aurora, night

        var title: String {
            switch self {
            case .dashboard: return "Dashboard"
            case .agenda: return "Agenda"
            case .moon: return "Moon"
            case .horizon: return "Horizon"
            case .light: return "Light Cycle"
            case .quote: return "Quote"
            case .night: return "Night"
            case .skylight: return "Skylight"
            case .fuzzy: return "Fuzzy Clock"
            case .weatherglass: return "Weatherglass"
            case .aurora: return "Aurora"
            case .orrery: return "Orrery"
            case .window: return "Window"
            case .cyberpunk: return "Cyberpunk"
            case .uplink: return "Uplink"
            case .steward: return "Steward"
            case .wing: return "Steward Wing"
            case .grimoire: return "Grimoire"
            }
        }

        /// The layout `steps` places along `allCases`, wrapping at either end: the remote's
        /// left and right step through them.
        func advanced(by steps: Int) -> Layout {
            let all = Self.allCases
            let index = all.firstIndex(of: self)!
            let count = all.count
            return all[((index + steps) % count + count) % count]
        }

        /// A saved layout, including the agenda's earlier name.
        init?(saved: String) {
            self.init(rawValue: saved == "halftone" ? "agenda" : saved)
        }
    }

    enum Connection: Equatable {
        case demo
        case server(URL)
    }

    private(set) var connection: Connection?
    private(set) var snapshot: Snapshot?
    private(set) var lastSuccess: Date?
    private(set) var problem: String?
    private(set) var failingSince: Date?
    var settingsVisible = false
    /// The weather's pressure readings, for the Weatherglass barometer's trend needle.
    private(set) var pressureHistory: PressureHistory

    var layout: Layout {
        didSet { save(layout.rawValue, Keys.layout) }
    }

    /// Hours without a remote press for which the app holds tvOS's idle timer; 0 is always.
    /// tvOS runs the screensaver and "Sleep After" off that one timer, so holding it keeps
    /// both away, and letting go hands both back: the screensaver at its usual delay, then
    /// sleep. An app can neither read "Sleep After" nor put the Apple TV to sleep itself.
    var keepAwakeHours: Int {
        didSet {
            defaults.set(keepAwakeHours, forKey: Keys.keepAwakeHours)
            noteInteraction()
        }
    }

    static let keepAwakeChoices = [0, 1, 2, 4, 8]

    /// Whether the live skies (Skylight, Aurora, Window) may draw their brightest things
    /// brighter than the text's white, which only an HDR output shows (`SkyLayer`).
    enum Highlights: String, CaseIterable {
        /// On once the screen reports extended range, which it does in an HDR Format.
        case automatic
        /// Always on: for an HDR Format the screen never reported. In an SDR Format the
        /// highlights clip to white.
        case hdr
        /// Never: everything stays within white.
        case sdr

        var title: String {
            switch self {
            case .automatic: return "Automatic"
            case .hdr: return "HDR"
            case .sdr: return "SDR"
            }
        }
    }

    var highlights: Highlights {
        didSet { save(highlights.rawValue, Keys.highlights) }
    }

    var username: String {
        didSet { defaults.set(username, forKey: Keys.username) }
    }

    var password: String {
        didSet {
            #if canImport(UIKit)
            Keychain.password = password.isEmpty ? nil : password
            #endif
        }
    }

    private let defaults: UserDefaults
    /// Where the store keeps what it records rather than what was chosen: the pressure history.
    private let state: UserDefaults
    private var loop: Task<Void, Never>?
    private var idleCheck: Task<Void, Never>?
    private var lastInteraction = Date.now

    static let pollInterval: Duration = .seconds(300)
    static let retryInterval: Duration = .seconds(60)

    private enum Keys {
        static let connection = "connection"
        static let username = "username"
        static let layout = "layout"
        static let keepAwakeHours = "keepAwakeHours"
        static let highlights = "highlights"
        static let pressureHistory = "pressureHistory"
        static let pressureSource = "pressureSource"
    }

    /// The choices come from *defaults*; the history goes to *state*, the same unless given.
    /// The Mac saver keeps them apart: a screensaver's defaults write back every key they hold
    /// when they save, so a saver recording pressure undid whatever Options had saved since.
    init(defaults: UserDefaults = .standard, state: UserDefaults? = nil) {
        self.defaults = defaults
        self.state = state ?? defaults
        username = defaults.string(forKey: Keys.username) ?? "admin"
        // `-layout moon` sets it for a run too, since launch arguments land in UserDefaults.
        layout = defaults.string(forKey: Keys.layout).flatMap(Layout.init(saved:)) ?? .dashboard
        #if canImport(UIKit)
        password = Keychain.password ?? ""
        #else
        password = ""
        #endif
        keepAwakeHours = defaults.integer(forKey: Keys.keepAwakeHours)
        highlights = defaults.string(forKey: Keys.highlights).flatMap(Highlights.init(rawValue:)) ?? .automatic
        pressureHistory = PressureHistory()
        // `-demo YES` and `-server <url>` set the source for a run (screenshots, the simulator).
        if defaults.bool(forKey: "demo") {
            connection = .demo
        } else if let typed = defaults.string(forKey: "server"), let url = DashboardClient.baseURL(forTyped: typed) {
            connection = .server(url)
        } else {
            connection = Self.decode(defaults.string(forKey: Keys.connection))
        }
        #if canImport(UIKit)
        settingsVisible = connection == nil
        #endif
        // Readings from another source (a `-demo` run, another Pi) would make a trend out of
        // two places, so the history is kept only for the source it came from.
        if let connection, self.state.string(forKey: Keys.pressureSource) == Self.encode(connection) {
            pressureHistory = self.state.data(forKey: Keys.pressureHistory)
                .flatMap { try? JSONDecoder().decode(PressureHistory.self, from: $0) } ?? PressureHistory()
        }
    }

    func start() {
        noteInteraction()
        #if canImport(UIKit)
        if idleCheck == nil {
            idleCheck = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    self?.updateIdleTimer()
                }
            }
        }
        #endif
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: self.problem == nil ? Self.pollInterval : Self.retryInterval)
            }
        }
    }

    /// Stops polling, for the screensaver's end.
    func stop() {
        loop?.cancel()
        loop = nil
    }

    /// Any remote press, and the app coming back to the foreground: restarts "Keep awake".
    func noteInteraction() {
        lastInteraction = .now
        updateIdleTimer()
    }

    /// Holds the idle timer until "Keep awake" has run out since the last remote press.
    private func updateIdleTimer(now: Date = .now) {
        #if canImport(UIKit)
        let hold = keepAwakeHours == 0 || now.timeIntervalSince(lastInteraction) < Double(keepAwakeHours * 3600)
        if UIApplication.shared.isIdleTimerDisabled != hold { UIApplication.shared.isIdleTimerDisabled = hold }
        #endif
    }

    /// Takes up choices saved since this store was made, for the Mac saver: its Options sheet
    /// writes the keys from its own view, and the store outlives a session when the legacy
    /// host never calls `stopAnimation`.
    func reloadChoices() {
        layout = defaults.string(forKey: Keys.layout).flatMap(Layout.init(saved:)) ?? layout
        highlights = defaults.string(forKey: Keys.highlights).flatMap(Highlights.init(rawValue:)) ?? highlights
        if let saved = Self.decode(defaults.string(forKey: Keys.connection)), saved != connection {
            connect(saved)
        }
    }

    /// Saves a choice unless it is already what is saved: taking up the Mac saver's choices
    /// (`reloadChoices`) must not write them back, which would leave its defaults holding
    /// changes to save over Options' next ones.
    private func save(_ value: String, _ key: String) {
        if defaults.string(forKey: key) != value { defaults.set(value, forKey: key) }
    }

    func connect(_ connection: Connection) {
        self.connection = connection
        save(Self.encode(connection), Keys.connection)
        // Another source's snapshot must not stay up as if it were this one's.
        snapshot = nil
        pressureHistory = PressureHistory()
        problem = nil
        failingSince = nil
        loop?.cancel()
        loop = nil
        start()
    }

    func refresh() async {
        guard let connection else { return }
        do {
            let fresh: Snapshot
            switch connection {
            case .demo:
                fresh = try Self.demoSnapshot().shiftedToToday(now: .now).fetched(at: .now)
            case .server(let url):
                fresh = try await DashboardClient(baseURL: url, username: username, password: password).fetch()
            }
            snapshot = fresh
            recordPressure(fresh)
            lastSuccess = .now
            problem = nil
            failingSince = nil
        } catch is CancellationError {
            return
        } catch {
            problem = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if failingSince == nil { failingSince = .now }
        }
    }

    /// One line for the corner: the connection is down, or a source the Pi is still showing has
    /// gone stale. Nothing when everything is current.
    var notice: String? {
        if let since = failingSince {
            return "Can't reach the dashboard since \(since.formatted(date: .omitted, time: .shortened))"
        }
        guard let sources = snapshot?.sources else { return nil }
        let stale = [
            ("Calendar", sources.events?.staleness),
            ("Weather", sources.weather?.staleness),
            ("Birthdays", sources.birthdays?.staleness),
        ].filter { $0.1?.isWorthFlagging == true }.map(\.0)
        return stale.isEmpty ? nil : "\(ListFormatter.localizedString(byJoining: stale)) not updated lately"
    }

    /// Keeps the weather's pressure, stamped with when the Pi fetched it: polling the same cache
    /// again adds nothing, and a new fetch is a new reading.
    private func recordPressure(_ snapshot: Snapshot) {
        guard let connection, let weather = snapshot.sources.weather, let hPa = weather.data?.pressure else { return }
        let before = pressureHistory
        pressureHistory.record(hPa, at: weather.fetchedAt ?? .now)
        guard pressureHistory != before, let data = try? JSONEncoder().encode(pressureHistory) else { return }
        state.set(data, forKey: Keys.pressureHistory)
        state.set(Self.encode(connection), forKey: Keys.pressureSource)
    }

    private static func demoSnapshot() throws -> Snapshot {
        guard let url = PlatformBundle.resources.url(forResource: "demo-snapshot", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try DashboardClient.validated(Data(contentsOf: url))
    }

    private static func encode(_ connection: Connection) -> String {
        switch connection {
        case .demo: return "demo"
        case .server(let url): return url.absoluteString
        }
    }

    private static func decode(_ raw: String?) -> Connection? {
        guard let raw else { return nil }
        if raw == "demo" { return .demo }
        return URL(string: raw).map(Connection.server)
    }
}
