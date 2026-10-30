import DashboardCore
import Foundation

/// The snapshot for "This Mac": no Pi, the weather and air from Open-Meteo for the place chosen
/// in Options, and the moon, the sun and the quote computed here (`LocalSnapshot`).
///
/// Open-Meteo's answers are kept in the state defaults, so a screensaver session starts from the
/// last one instead of an empty screen, and a source is fetched only once its last answer is
/// older than its interval, however often the store polls or the saver starts.
///
/// The calendar and birthdays are off: the screensaver host's sandbox has no calendar access.
@MainActor
final class LocalSource {
    /// Where and in which units, from Options.
    struct Configuration: Equatable {
        var place: LocalSnapshot.Place?
        var metric: Bool

        init(defaults: UserDefaults) {
            place = defaults.data(forKey: Keys.place).flatMap { try? JSONDecoder().decode(LocalSnapshot.Place.self, from: $0) }
            metric = defaults.object(forKey: Keys.metric) as? Bool ?? (Locale.current.measurementSystem != .us)
        }

        /// What a cached answer was fetched for; another place's or units' is not used.
        var cacheKey: String? {
            place.map { "\($0.latitude),\($0.longitude),\(metric ? "metric" : "imperial")" }
        }
    }

    enum Keys {
        static let place = "place"
        static let metric = "metric"
    }

    enum Failure: LocalizedError {
        case noPlace

        var errorDescription: String? { "No place chosen yet." }
    }

    /// How often each source is fetched: the Pi's default fetch interval for the weather, and
    /// the air's TTL, since Open-Meteo updates it hourly anyway.
    static let weatherInterval: TimeInterval = 30 * 60
    static let airInterval: TimeInterval = 30 * 60

    private let defaults: UserDefaults
    private let state: UserDefaults
    private lazy var quotes: [Quote] = Self.loadQuotes()

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
            events: .off,
            birthdays: .off
        )
    }

    /// The last answer for *name* kept for *key*, fetched again first when it is older than
    /// *interval*, and the fetch's error if it failed. A failed fetch keeps the old answer,
    /// which ages on screen as the Pi's does.
    private func cached(_ name: String, for key: String, every interval: TimeInterval, now: Date,
                        fetch: () async throws -> Data) async -> ((data: Data, at: Date)?, Error?) {
        let dataKey = "local.\(name)", atKey = "local.\(name).at", forKey = "local.\(name).for"
        var data = state.string(forKey: forKey) == key ? state.data(forKey: dataKey) : nil
        var at = data == nil ? nil : state.object(forKey: atKey) as? Date
        var failure: Error?
        if at.map({ now.timeIntervalSince($0) >= interval }) ?? true {
            do {
                let fresh = try await fetch()
                data = fresh
                at = now
                state.set(fresh, forKey: dataKey)
                state.set(now, forKey: atKey)
                state.set(key, forKey: forKey)
            } catch {
                failure = error
            }
        }
        guard let data, let at else { return (nil, failure) }
        return ((data, at), failure)
    }

    /// The Pi's quote store, bundled.
    private static func loadQuotes() -> [Quote] {
        guard let url = PlatformBundle.resources.url(forResource: "quotes", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Quote].self, from: data)) ?? []
    }
}
