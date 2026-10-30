import CryptoKit
import DashboardCore
import Foundation

/// The snapshot for "This Mac": no Pi. The weather and air come from Open-Meteo for the place
/// chosen in Options, the events from the calendar feeds (ICS) given there, and the moon, the sun
/// and the quote are computed here (`LocalSnapshot`).
///
/// Each answer is kept in a file under Caches, with when it was fetched and for what in the
/// state defaults, so a screensaver session starts from the last one instead of an empty screen,
/// and a source is fetched only once its answer is older than its interval, however often the
/// store polls or the saver starts. Feeds go to files rather than defaults since a calendar's
/// can run to megabytes.
///
/// Birthdays are off: the screensaver host's sandbox has no access to Contacts or the Mac's
/// calendars, which is also why events come from feeds.
@MainActor
final class LocalSource {
    /// Where, in which units and from which feeds, from Options.
    struct Configuration: Equatable {
        var place: LocalSnapshot.Place?
        var metric: Bool
        var feeds: [URL]

        init(defaults: UserDefaults) {
            place = defaults.data(forKey: Keys.place).flatMap { try? JSONDecoder().decode(LocalSnapshot.Place.self, from: $0) }
            metric = defaults.object(forKey: Keys.metric) as? Bool ?? (Locale.current.measurementSystem != .us)
            feeds = (defaults.stringArray(forKey: Keys.feeds) ?? []).compactMap(Self.feedURL)
        }

        /// What a cached weather answer was fetched for; another place's or units' is not used.
        var cacheKey: String? {
            place.map { "\($0.latitude),\($0.longitude),\(metric ? "metric" : "imperial")" }
        }

        /// A typed feed address as a URL to fetch: `webcal://` is HTTPS, and a bare host gets
        /// HTTPS too.
        static func feedURL(_ typed: String) -> URL? {
            var text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            if text.lowercased().hasPrefix("webcal://") { text = "https://" + text.dropFirst("webcal://".count) }
            if !text.contains("://") { text = "https://" + text }
            guard let url = URL(string: text), url.scheme == "https" || url.scheme == "http", url.host() != nil else { return nil }
            return url
        }
    }

    enum Keys {
        static let place = "place"
        static let metric = "metric"
        static let feeds = "feeds"
    }

    enum Failure: LocalizedError {
        case noPlace

        var errorDescription: String? { "No place chosen yet." }
    }

    /// How often each source is fetched: the Pi's default fetch interval for the weather, the
    /// air's TTL (Open-Meteo updates it hourly anyway), and a quarter hour for the feeds, which
    /// is about as often as Google and iCloud refresh what they publish.
    static let weatherInterval: TimeInterval = 30 * 60
    static let airInterval: TimeInterval = 30 * 60
    static let feedInterval: TimeInterval = 15 * 60

    private let defaults: UserDefaults
    private let state: UserDefaults
    private lazy var quotes: [Quote] = Self.loadQuotes()
    /// Each feed's events, kept until its answer or the day's window changes.
    private var parsed: [URL: (at: Date, window: Range<Date>, events: [CalendarEvent])] = [:]

    init(defaults: UserDefaults, state: UserDefaults) {
        self.defaults = defaults
        self.state = state
    }

    func snapshot(now: Date = .now) async throws -> Snapshot {
        let config = Configuration(defaults: defaults)
        guard let place = config.place, let key = config.cacheKey else { throw Failure.noPlace }

        let (forecast, failure) = await cached("forecast", for: key, every: Self.weatherInterval, now: now) {
            try await OpenMeteo.get(OpenMeteo.forecastURL(latitude: place.latitude, longitude: place.longitude, metric: config.metric))
        }
        let (air, _) = await cached("air", for: key, every: Self.airInterval, now: now) {
            try await OpenMeteo.get(OpenMeteo.airQualityURL(latitude: place.latitude, longitude: place.longitude))
        }
        let weather = forecast.flatMap { answer in
            (try? OpenMeteo.weather(from: answer.data, now: now, zone: place.timeZone, place: place.name)).map { ($0, answer.at) }
        }
        // Nothing to draw the weather from: say so rather than show a plate without it.
        if weather == nil, let failure { throw failure }

        return LocalSnapshot.make(
            now: now,
            place: place,
            metric: config.metric,
            quotes: quotes,
            weather: weather.map { .read($0.0, at: $0.1) } ?? .pending,
            airQuality: air.flatMap { answer in (try? OpenMeteo.airQuality(from: answer.data)).map { .read($0, at: answer.at) } } ?? .pending,
            events: await events(config.feeds, zone: place.timeZone, now: now),
            birthdays: .off
        )
    }

    /// Every feed's events in the window, as old as the oldest feed's answer, so a feed that
    /// keeps failing ages the calendar on screen as the Pi's does. Off without feeds.
    private func events(_ feeds: [URL], zone: TimeZone, now: Date) async -> LocalSnapshot.Feed<[CalendarEvent]> {
        guard !feeds.isEmpty else { return .off }
        let bounds = LocalSnapshot.eventWindow(now: now, in: zone)
        let window = bounds.start..<bounds.end
        var all: [CalendarEvent] = []
        var oldest: Date?
        for url in feeds {
            let (answer, _) = await cached("feed-" + Self.digest(url.absoluteString), for: url.absoluteString,
                                           every: Self.feedInterval, now: now) {
                try await Self.fetchFeed(url)
            }
            guard let answer else { continue }
            if let kept = parsed[url], kept.at == answer.at, kept.window == window {
                all += kept.events
            } else {
                let text = String(decoding: answer.data, as: UTF8.self)
                let events = ICS.parse(text, zone: zone, window: window, fallbackName: url.host()).events
                parsed[url] = (answer.at, window, events)
                all += events
            }
            oldest = min(oldest ?? answer.at, answer.at)
        }
        guard let oldest else { return .pending }
        return .read(all.sorted { $0.start < $1.start }, at: oldest)
    }

    /// The last answer for *name* kept for *key*, fetched again first when it is older than
    /// *interval*, and the fetch's error if it failed. A failed fetch keeps the old answer,
    /// which ages on screen as the Pi's does.
    private func cached(_ name: String, for key: String, every interval: TimeInterval, now: Date,
                        fetch: () async throws -> Data) async -> ((data: Data, at: Date)?, Error?) {
        let file = Self.cacheFolder.appending(path: name)
        let atKey = "local.\(name).at", forKey = "local.\(name).for"
        var data = state.string(forKey: forKey) == key ? try? Data(contentsOf: file) : nil
        var at = data == nil ? nil : state.object(forKey: atKey) as? Date
        var failure: Error?
        if at.map({ now.timeIntervalSince($0) >= interval }) ?? true {
            do {
                let fresh = try await fetch()
                try FileManager.default.createDirectory(at: Self.cacheFolder, withIntermediateDirectories: true)
                try fresh.write(to: file, options: .atomic)
                data = fresh
                at = now
                state.set(now, forKey: atKey)
                state.set(key, forKey: forKey)
            } catch {
                failure = error
            }
        }
        guard let data, let at else { return (nil, failure) }
        return ((data, at), failure)
    }

    private static func fetchFeed(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw URLError(.badServerResponse) }
        return data
    }

    /// Caches, in the screensaver host's container when run there.
    private static let cacheFolder: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appending(path: (PlatformBundle.resources.bundleIdentifier ?? "HomeDashboard") + ".local")
    }()

    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// The Pi's quote store, bundled.
    private static func loadQuotes() -> [Quote] {
        guard let url = PlatformBundle.resources.url(forResource: "quotes", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Quote].self, from: data)) ?? []
    }
}
