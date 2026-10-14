import Foundation
import Network
import Observation

/// Finds dashboards advertising `_homedash._tcp` (HomeDashboard's `make web-enable` installs
/// the avahi service) and turns one into a base URL.
@MainActor
@Observable
final class PiBrowser {
    struct Found: Identifiable, Hashable {
        var name: String
        var endpoint: NWEndpoint
        var id: String { name }
    }

    private(set) var found: [Found] = []
    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: "_homedash._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.compactMap { result -> Found? in
                guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                return Found(name: name, endpoint: result.endpoint)
            }
            .sorted { $0.name < $1.name }
            Task { @MainActor in self?.found = found }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }

    /// The service's address as `http://<ipv4>:<port>/`. IPv4 only, so the URL needs no
    /// bracketed, zone-scoped IPv6 literal.
    static func resolve(_ endpoint: NWEndpoint) async -> URL? {
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let connection = NWConnection(to: endpoint, using: parameters)
        return await withCheckedContinuation { continuation in
            var finished = false
            func finish(_ url: URL?) {
                guard !finished else { return }
                finished = true
                connection.cancel()
                continuation.resume(returning: url)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard case let .hostPort(host, port) = connection.currentPath?.remoteEndpoint else {
                        return finish(nil)
                    }
                    var address = "\(host)"
                    if let percent = address.firstIndex(of: "%") { address = String(address[..<percent]) }
                    finish(URL(string: "http://\(address):\(port.rawValue)/"))
                case .failed, .cancelled, .waiting:
                    // `.waiting` is a refused or unreachable address; it would retry until the
                    // timeout, and the person is looking at a "connecting…" row meanwhile.
                    finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { finish(nil) }
        }
    }
}
