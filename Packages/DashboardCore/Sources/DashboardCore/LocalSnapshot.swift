import CryptoKit
import Foundation

/// A snapshot made on this device instead of read from a Pi: what the Mac screensaver shows
/// when its source is "This Mac". The weather and the air come from Open-Meteo, the events and
/// birthdays from the caller (EventKit on the Mac), and the moon, the sun and the quote are
/// computed here as the Pi's `/api/dashboard` computes them, so every layout draws it unchanged.
public enum LocalSnapshot {
    /// Where the dashboard is: the place picked in Options.
    public struct Place: Codable, Sendable, Equatable {
        public var name: String
        public var latitude: Double
        public var longitude: Double
        /// IANA zone name; the dashboard's days are counted in it.
        public var timezone: String

        public init(name: String, latitude: Double, longitude: Double, timezone: String) {
            self.name = name
            self.latitude = latitude
            self.longitude = longitude
            self.timezone = timezone
        }

        public var timeZone: TimeZone { TimeZone(identifier: timezone) ?? .current }
    }

    /// One source's state: off (absent from the snapshot, as a source the Pi has disabled),
    /// not read yet, or read at a time.
    public enum Feed<Value: Sendable>: Sendable {
        case off
        case pending
        case read(Value, at: Date)
    }

    /// How long each source counts as fresh, the Pi's default TTLs: aging past one, stale past
    /// two, expired (not drawn) past four.
    public enum TTL {
        public static let weather: TimeInterval = 60 * 60
        public static let events: TimeInterval = 120 * 60
        public static let birthdays: TimeInterval = 1440 * 60
        public static let airQuality: TimeInterval = 30 * 60
    }

    public static func make(
        now: Date,
        place: Place,
        metric: Bool,
        quotes: [Quote],
        weather: Feed<Weather>,
        airQuality: Feed<AirQuality>,
        events: Feed<[CalendarEvent]>,
        birthdays: Feed<[Birthday]>
    ) -> Snapshot {
        let zone = place.timeZone
        let today = CivilDate(now, in: zone)
        return Snapshot(
            schemaVersion: Snapshot.supportedSchemaVersion,
            generatedAt: now,
            timezone: place.timezone,
            utcOffsetSeconds: zone.secondsFromGMT(for: now),
            units: metric ? "metric" : "imperial",
            quote: quote(for: today, prefix: "", in: quotes),
            moon: moon(today: today, place: place, quote: quote(for: today, prefix: "moonphase-", in: quotes)),
            sun: sun(today: today, place: place),
            sources: Sources(
                events: source(events, ttl: TTL.events, now: now),
                weather: source(weather, ttl: TTL.weather, now: now),
                birthdays: source(birthdays, ttl: TTL.birthdays, now: now),
                airQuality: source(airQuality, ttl: TTL.airQuality, now: now)
            )
        )
    }

    /// A source's entry as the Pi sends it: absent when off, with no data until read, and with
    /// the data withheld once it has expired.
    static func source<Value>(_ feed: Feed<Value>, ttl: TimeInterval, now: Date) -> Source<Value>? {
        switch feed {
        case .off:
            return nil
        case .pending:
            return Source(fetchedAt: nil, staleness: .unknown, data: nil)
        case .read(let value, let at):
            let staleness = Staleness(age: now.timeIntervalSince(at), ttl: ttl)
            return Source(fetchedAt: at, staleness: staleness, data: staleness == .expired ? nil : value)
        }
    }

    // MARK: Quote

    /// The Pi's `quote_for` at its daily cadence: the MD5 of *prefix* and the date, as one
    /// big number, modulo the store's size. Each panel's own *prefix* keeps two quotes on one
    /// plate apart.
    public static func quote(for day: CivilDate, prefix: String, in quotes: [Quote]) -> Quote? {
        guard !quotes.isEmpty else { return nil }
        return quotes[quoteIndex(key: prefix + day.isoString, count: quotes.count)]
    }

    static func quoteIndex(key: String, count: Int) -> Int {
        Insecure.MD5.hash(data: Data(key.utf8)).reduce(0) { ($0 * 256 + Int($1)) % count }
    }

    // MARK: Moon and sun

    /// The Pi's `_moon`: today's moon and the three days either side, the next new or full
    /// moon, and the rise and set at the place.
    static func moon(today: CivilDate, place: Place, quote: Quote?) -> Moon {
        let zone = place.timeZone
        let full = Astronomy.nextPrincipal(after: today, full: true, in: zone)
        let new = Astronomy.nextPrincipal(after: today, full: false, in: zone)
        let next = full.days <= new.days
            ? Moon.NextPhase(kind: "full", date: full.date, days: full.days)
            : Moon.NextPhase(kind: "new", date: new.date, days: new.days)
        let times = Astronomy.moonTimes(on: today, latitude: place.latitude, longitude: place.longitude, in: zone)
        let days = (-3...3).map { delta -> MoonDay in
            let d = today.adding(days: delta)
            return MoonDay(
                date: d,
                ageDays: Astronomy.moonAge(on: d),
                fraction: Astronomy.moonFraction(on: d),
                illumination: Astronomy.moonIllumination(on: d)
            )
        }
        return Moon(
            phaseName: Astronomy.moonPhaseName(on: today),
            supermoon: Astronomy.isSupermoon(on: today),
            rise: times.rise,
            set: times.set,
            next: next,
            days: days,
            quote: quote
        )
    }

    /// The Pi's `_sun`: the altitude every 15 minutes from midnight today to the fourth
    /// midnight after (so a DST day has 92 or 100 samples, not 96), and each day's solar noon.
    static func sun(today: CivilDate, place: Place) -> Sun {
        let zone = place.timeZone
        let step = 15
        let start = today.start(in: zone)
        let end = today.adding(days: 4).start(in: zone)
        let steps = Int(end.timeIntervalSince(start)) / (step * 60)
        let altitudes = (0...steps).map { k in
            Astronomy.solarAltitude(at: start.addingTimeInterval(Double(k * step * 60)), latitude: place.latitude, longitude: place.longitude)
        }
        let noons = (0..<4).map { delta -> Sun.Noon in
            let time = Astronomy.solarNoon(on: today.adding(days: delta), longitude: place.longitude)
            return Sun.Noon(time: time, altitude: Astronomy.solarAltitude(at: time, latitude: place.latitude, longitude: place.longitude))
        }
        return Sun(start: start, stepMinutes: step, altitudes: altitudes, noons: noons)
    }

    // MARK: Events

    /// The window events are read for: from the Monday of this week, as the Pi's calendar
    /// window starts, to two weeks ahead, which covers every layout's look forward.
    public static func eventWindow(now: Date, in zone: TimeZone) -> (start: Date, end: Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let today = CivilDate(now, in: zone)
        let sinceMonday = (cal.component(.weekday, from: today.start(in: zone)) + 5) % 7
        return (today.adding(days: -sinceMonday).start(in: zone), today.adding(days: 15).start(in: zone))
    }

    /// How far ahead birthdays are read: the Pi's default lookahead.
    public static let birthdayLookaheadDays = 30
}

extension Staleness {
    /// The Pi's `check_staleness`: fresh to one TTL, aging to two, stale to four.
    init(age: TimeInterval, ttl: TimeInterval) {
        switch age {
        case ...ttl: self = .fresh
        case ...(ttl * 2): self = .aging
        case ...(ttl * 4): self = .stale
        default: self = .expired
        }
    }
}

extension CivilDate {
    /// `YYYY-MM-DD`, as Python's `date.isoformat()` writes it.
    public var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}
