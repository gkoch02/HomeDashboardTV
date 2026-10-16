import DashboardCore
import Foundation
import Observation
import UIKit

/// Where the snapshot comes from, and the polling loop that keeps it current.
///
/// The Pi refreshes its cache on its own timer, so polling faster than every few minutes
/// only re-reads the same file. The last good snapshot stays on screen through a failure;
/// `problem` says what went wrong and since when.
@MainActor
@Observable
final class DashboardStore {
    /// What the screen shows: the week, the day's agenda plate, the Pi's moonphase theme, the
    /// next 72 hours on one axis, today on a 24-hour dial, the day's quote, a night plate, or the live sky.
    /// Each case is a `Theme`, drawn in `DashboardScreen.content`.
    enum Layout: String, CaseIterable {
        case dashboard, agenda, moon, horizon, light, quote, night, skylight

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

    var layout: Layout {
        didSet { defaults.set(layout.rawValue, forKey: Keys.layout) }
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

    var username: String {
        didSet { defaults.set(username, forKey: Keys.username) }
    }

    var password: String {
        didSet { Keychain.password = password.isEmpty ? nil : password }
    }

    private let defaults = UserDefaults.standard
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
    }

    init() {
        username = defaults.string(forKey: Keys.username) ?? "admin"
        // `-layout moon` sets it for a run too, since launch arguments land in UserDefaults.
        layout = defaults.string(forKey: Keys.layout).flatMap(Layout.init(saved:)) ?? .dashboard
        password = Keychain.password ?? ""
        keepAwakeHours = defaults.integer(forKey: Keys.keepAwakeHours)
        // `-demo YES` and `-server <url>` set the source for a run (screenshots, the simulator).
        if defaults.bool(forKey: "demo") {
            connection = .demo
        } else if let typed = defaults.string(forKey: "server"), let url = DashboardClient.baseURL(forTyped: typed) {
            connection = .server(url)
        } else {
            connection = Self.decode(defaults.string(forKey: Keys.connection))
        }
        settingsVisible = connection == nil
    }

    func start() {
        noteInteraction()
        if idleCheck == nil {
            idleCheck = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    self?.updateIdleTimer()
                }
            }
        }
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: self.problem == nil ? Self.pollInterval : Self.retryInterval)
            }
        }
    }

    /// Any remote press, and the app coming back to the foreground: restarts "Keep awake".
    func noteInteraction() {
        lastInteraction = .now
        updateIdleTimer()
    }

    /// Holds the idle timer until "Keep awake" has run out since the last remote press.
    private func updateIdleTimer(now: Date = .now) {
        let hold = keepAwakeHours == 0 || now.timeIntervalSince(lastInteraction) < Double(keepAwakeHours * 3600)
        if UIApplication.shared.isIdleTimerDisabled != hold { UIApplication.shared.isIdleTimerDisabled = hold }
    }

    func connect(_ connection: Connection) {
        self.connection = connection
        defaults.set(Self.encode(connection), forKey: Keys.connection)
        // Another source's snapshot must not stay up as if it were this one's.
        snapshot = nil
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
                fresh = try Self.demoSnapshot().shiftedToToday(now: .now)
            case .server(let url):
                fresh = try await DashboardClient(baseURL: url, username: username, password: password).fetch()
            }
            snapshot = fresh
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

    private static func demoSnapshot() throws -> Snapshot {
        guard let url = Bundle.main.url(forResource: "demo-snapshot", withExtension: "json") else {
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
