import Foundation

public enum DashboardClientError: Error, Equatable, LocalizedError {
    case unauthorized
    case http(Int)
    case unsupportedSchema(Int)

    public var errorDescription: String? {
        switch self {
        case .unauthorized: return "The dashboard asked for a password."
        case .http(let code): return "The dashboard answered HTTP \(code)."
        case .unsupportedSchema(let v):
            return "The dashboard sends data version \(v); this app reads up to \(Snapshot.supportedSchemaVersion)."
        }
    }
}

/// Reads `/api/dashboard` from the Pi's web UI, with Basic Auth when a password is set.
public struct DashboardClient: Sendable {
    public var baseURL: URL
    public var username: String?
    public var password: String?
    public var session: URLSession

    public init(baseURL: URL, username: String? = nil, password: String? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.username = username
        self.password = password
        self.session = session
    }

    public var request: URLRequest {
        var request = URLRequest(url: baseURL.appending(path: "api/dashboard"))
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let username, !username.isEmpty, let password {
            let token = Data("\(username):\(password)".utf8).base64EncodedString()
            request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    public func fetch() async throws -> Snapshot {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw http.statusCode == 401 ? DashboardClientError.unauthorized : .http(http.statusCode)
        }
        return try Self.validated(data)
    }

    /// The first of *urls* to answer, tried in order, and its index there: a main Pi and its
    /// backup. Every poll starts again from the first, so the main one takes over again as soon
    /// as it is back. When none answers, the first one's error is the one thrown: that is the
    /// Pi expected to be there.
    public static func fetchFirst(of urls: [URL], username: String? = nil, password: String? = nil,
                                  session: URLSession = .shared) async throws -> (snapshot: Snapshot, index: Int) {
        var firstError: Error?
        for (index, url) in urls.enumerated() {
            do {
                let snapshot = try await DashboardClient(baseURL: url, username: username, password: password,
                                                         session: session).fetch()
                return (snapshot, index)
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled { throw error }
                if firstError == nil { firstError = error }
            }
        }
        throw firstError ?? URLError(.badURL)
    }

    /// Decodes *data* and refuses a payload shape newer than this build understands.
    public static func validated(_ data: Data) throws -> Snapshot {
        let snapshot = try Snapshot.decode(data)
        guard snapshot.schemaVersion <= Snapshot.supportedSchemaVersion else {
            throw DashboardClientError.unsupportedSchema(snapshot.schemaVersion)
        }
        return snapshot
    }

    /// The base URL for a typed address: `dashboard.local`, `192.168.1.20:8080` or a full URL.
    /// A bare host gets the web UI's default port.
    public static func baseURL(forTyped address: String) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard var components = URLComponents(string: withScheme), components.host?.isEmpty == false else {
            return nil
        }
        if components.port == nil { components.port = 8080 }
        if components.path.isEmpty { components.path = "/" }
        return components.url
    }
}
