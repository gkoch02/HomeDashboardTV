import DashboardCore
import Foundation
import Observation

/// Where the snapshot comes from, and the polling loop that keeps it current.
///
/// The Pi refreshes its cache on its own timer, so polling faster than every few minutes
/// only re-reads the same file. The last good snapshot stays on screen through a failure;
/// `problem` says what went wrong and since when.
@MainActor
@Observable
final class DashboardStore {
    /// What the screen shows: the week, the day's agenda plate, or the Pi's moonphase theme.
    /// Each case is a `Theme`, drawn in `DashboardScreen.content`.
    enum Layout: String, CaseIterable {
        case dashboard, agenda, moon

        var title: String {
            switch self {
            case .dashboard: return "Dashboard"
            case .agenda: return "Agenda"
            case .moon: return "Moon"
            }
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

    var username: String {
        didSet { defaults.set(username, forKey: Keys.username) }
    }

    var password: String {
        didSet { Keychain.password = password.isEmpty ? nil : password }
    }

    private let defaults = UserDefaults.standard
    private var loop: Task<Void, Never>?

    static let pollInterval: Duration = .seconds(300)
    static let retryInterval: Duration = .seconds(60)

    private enum Keys {
        static let connection = "connection"
        static let username = "username"
        static let layout = "layout"
    }

    init() {
        username = defaults.string(forKey: Keys.username) ?? "admin"
        // `-layout moon` sets it for a run too, since launch arguments land in UserDefaults.
        layout = defaults.string(forKey: Keys.layout).flatMap(Layout.init(saved:)) ?? .dashboard
        password = Keychain.password ?? ""
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
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: self.problem == nil ? Self.pollInterval : Self.retryInterval)
            }
        }
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
