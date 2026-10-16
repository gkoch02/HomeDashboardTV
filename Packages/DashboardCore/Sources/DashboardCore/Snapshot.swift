import Foundation

/// The payload of the Pi's `GET /api/dashboard` (HomeDashboard `src/web/routes/dashboard.py`).
///
/// Field names follow the Python serializers in `src/fetchers/cache.py`, decoded with
/// `convertFromSnakeCase`. Every source is optional: a source the Pi has disabled is
/// absent, and one it has never fetched or whose cache expired has `data == nil`.
public struct Snapshot: Decodable, Sendable, Equatable {
    /// The newest payload shape this build understands. The Pi bumps it only when a field
    /// is removed or changes meaning, so a higher number means this build would misread it.
    public static let supportedSchemaVersion = 1

    public var schemaVersion: Int
    public var generatedAt: Date
    /// IANA name of the dashboard's configured zone; nil when the Pi is set to `local`.
    public var timezone: String?
    public var utcOffsetSeconds: Int
    public var units: String
    public var quote: Quote?
    /// Absent from a Pi older than the moon block.
    public var moon: Moon?
    /// The sun's altitude through the next days; absent from an older Pi, null without
    /// coordinates.
    public var sun: Sun?
    public var sources: Sources

    /// The zone the dashboard's days are counted in, which is the Pi's, not necessarily the TV's.
    public var timeZone: TimeZone { timeZone(local: .current) }

    /// A Pi on `timezone: local` sends no zone name, only today's offset. A fixed offset
    /// would count next week's days an hour out across a DST change, so the TV's own zone
    /// is used when it agrees with the Pi now, as it does when both are in one house.
    func timeZone(local: TimeZone) -> TimeZone {
        if let named = timezone.flatMap(TimeZone.init(identifier:)) { return named }
        if local.secondsFromGMT(for: generatedAt) == utcOffsetSeconds { return local }
        return TimeZone(secondsFromGMT: utcOffsetSeconds) ?? local
    }

    public var isMetric: Bool { units == "metric" }
}

public struct Quote: Decodable, Sendable, Equatable {
    public var text: String
    public var author: String
}

/// The sun's altitude every `stepMinutes` from `start` (local midnight today) for four days,
/// and each day's solar noon: what the Pi's `wide_horizon` shades its sky by (`sun` in
/// `/api/dashboard`). Samples step in real time.
public struct Sun: Decodable, Sendable, Equatable {
    public var start: Date
    public var stepMinutes: Int
    public var altitudes: [Double]
    public var noons: [Noon]

    public struct Noon: Decodable, Sendable, Equatable {
        public var time: Date
        public var altitude: Double
    }
}

/// The moonphase panel's data, as the Pi computes it (`moon` in `/api/dashboard`).
public struct Moon: Decodable, Sendable, Equatable {
    public var phaseName: String
    public var supermoon: Bool
    /// Present only when the Pi has coordinates.
    public var rise: Date?
    public var set: Date?
    public var next: NextPhase
    /// Today and the three days either side, in order.
    public var days: [MoonDay]
    public var quote: Quote?

    public struct NextPhase: Decodable, Sendable, Equatable {
        /// "full" or "new".
        public var kind: String
        public var date: CivilDate
        public var days: Int

        public var isFull: Bool { kind == "full" }
    }

    /// Today's entry: the middle of `days`.
    public var today: MoonDay? { days.count == 7 ? days[3] : days.first }
}

public struct MoonDay: Decodable, Sendable, Equatable, Hashable {
    public var date: CivilDate
    public var ageDays: Double
    /// Through the lunation at noon UTC: 0 new, 0.5 full; waxing below 0.5.
    public var fraction: Double
    /// Percent of the disc lit.
    public var illumination: Double
}

public struct Sources: Decodable, Sendable, Equatable {
    public var events: Source<[CalendarEvent]>?
    public var weather: Source<Weather>?
    public var birthdays: Source<[Birthday]>?
    public var airQuality: Source<AirQuality>?
}

/// One source's cache entry: its data plus how old the Pi considers it.
public struct Source<Value: Decodable & Sendable & Equatable>: Decodable, Sendable, Equatable {
    public var fetchedAt: Date?
    public var staleness: Staleness
    public var data: Value?
}

public enum Staleness: String, Decodable, Sendable {
    case fresh, aging, stale, expired, unknown

    /// A level a newer Pi adds reads as unknown instead of failing the whole payload.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Staleness(rawValue: raw) ?? .unknown
    }

    /// Worth flagging on screen: the panel shows its stale glyph from `stale` on.
    public var isWorthFlagging: Bool { self == .stale || self == .expired }
}

public struct CalendarEvent: Decodable, Sendable, Equatable, Hashable {
    public var summary: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var location: String?
    public var calendarName: String?
}

public struct Weather: Decodable, Sendable, Equatable {
    public var currentTemp: Double
    public var currentIcon: String
    public var currentDescription: String
    public var high: Double
    public var low: Double
    public var humidity: Int
    /// Sea-level pressure in hPa; absent when OWM gave none.
    public var pressure: Double?
    public var feelsLike: Double?
    public var windSpeed: Double?
    public var windDeg: Double?
    public var uvIndex: Double?
    public var sunrise: Date?
    public var sunset: Date?
    public var locationName: String?
    public var forecast: [DayForecast]
    public var alerts: [WeatherAlert]
    /// Absent from caches written before the Pi kept the 3-hour grid.
    public var hourly: [HourlyForecast]

    enum CodingKeys: String, CodingKey {
        case currentTemp, currentIcon, currentDescription, high, low, humidity, pressure, feelsLike
        case windSpeed, windDeg, uvIndex, sunrise, sunset, locationName, forecast, alerts, hourly
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currentTemp = try c.decode(Double.self, forKey: .currentTemp)
        currentIcon = try c.decode(String.self, forKey: .currentIcon)
        currentDescription = try c.decode(String.self, forKey: .currentDescription)
        high = try c.decode(Double.self, forKey: .high)
        low = try c.decode(Double.self, forKey: .low)
        humidity = try c.decode(Int.self, forKey: .humidity)
        pressure = try c.decodeIfPresent(Double.self, forKey: .pressure)
        feelsLike = try c.decodeIfPresent(Double.self, forKey: .feelsLike)
        windSpeed = try c.decodeIfPresent(Double.self, forKey: .windSpeed)
        windDeg = try c.decodeIfPresent(Double.self, forKey: .windDeg)
        uvIndex = try c.decodeIfPresent(Double.self, forKey: .uvIndex)
        sunrise = try c.decodeIfPresent(Date.self, forKey: .sunrise)
        sunset = try c.decodeIfPresent(Date.self, forKey: .sunset)
        locationName = try c.decodeIfPresent(String.self, forKey: .locationName)
        forecast = try c.decodeIfPresent([DayForecast].self, forKey: .forecast) ?? []
        alerts = try c.decodeIfPresent([WeatherAlert].self, forKey: .alerts) ?? []
        hourly = try c.decodeIfPresent([HourlyForecast].self, forKey: .hourly) ?? []
    }
}

public struct DayForecast: Decodable, Sendable, Equatable, Hashable {
    public var date: CivilDate
    public var high: Double
    public var low: Double
    public var icon: String
    public var description: String
    public var precipChance: Double?
}

public struct HourlyForecast: Decodable, Sendable, Equatable, Hashable {
    public var time: Date
    public var temp: Double
    public var icon: String
    public var precipChance: Double?
    /// Expected rain or snow over the slot, when the forecast gives one.
    public var precipMm: Double?
}

public struct WeatherAlert: Decodable, Sendable, Equatable, Hashable {
    public var event: String
}

public struct Birthday: Decodable, Sendable, Equatable, Hashable {
    public var name: String
    /// The upcoming occurrence, as the Pi's birthday fetcher stores it.
    public var date: CivilDate
    public var age: Int?
}

public struct AirQuality: Decodable, Sendable, Equatable {
    public var aqi: Int
    public var category: String
    public var pm25: Double
}

/// A calendar day with no time or zone, as Python's `date.isoformat()` writes it.
public struct CivilDate: Decodable, Sendable, Equatable, Hashable, Comparable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        let parts = raw.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Not a YYYY-MM-DD date: \(raw)")
            )
        }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    /// The day containing *date* in *zone*.
    public init(_ date: Date, in zone: TimeZone) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    /// Midnight starting this day in *zone*.
    public func start(in zone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.date(from: DateComponents(year: year, month: month, day: day))!
    }

    public func adding(days: Int) -> CivilDate {
        let utc = TimeZone(identifier: "UTC")!
        return CivilDate(start(in: utc).addingTimeInterval(TimeInterval(days * 86_400)), in: utc)
    }

    public static func < (a: CivilDate, b: CivilDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }
}

extension Snapshot {
    /// The decoder for the Pi's JSON: snake_case keys and Python `isoformat()` timestamps.
    public static func decode(_ data: Data) throws -> Snapshot {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let date = PythonISODate.parse(raw) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Not an ISO timestamp: \(raw)")
                )
            }
            return date
        }
        return try decoder.decode(Snapshot.self, from: data)
    }
}

/// Parses `datetime.isoformat()` output. Python writes microseconds (six digits) only when
/// they are non-zero, which `ISO8601DateFormatter` does not accept, so the fraction is cut
/// off, parsed alone and added back. A naive timestamp (no offset) is read as UTC, as the
/// Pi's own readers do.
enum PythonISODate {
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ raw: String) -> Date? {
        var text = raw
        var fraction = 0.0
        if let dot = text.firstIndex(of: ".") {
            let digitsEnd = text[dot...].dropFirst().firstIndex(where: { !$0.isNumber }) ?? text.endIndex
            fraction = Double("0" + text[dot..<digitsEnd]) ?? 0
            text.removeSubrange(dot..<digitsEnd)
        }
        let hasOffset = text.hasSuffix("Z") || text.dropFirst(19).contains(where: { $0 == "+" || $0 == "-" })
        if !hasOffset { text += "Z" }
        return formatter.date(from: text).map { $0.addingTimeInterval(fraction) }
    }
}

extension AirQuality {
    /// The EPA band the Pi's AQI falls in, which sets the colour it is drawn in. The Pi sends
    /// the band's name as `category`; the band is recomputed here so the colour cannot drift
    /// from the number if a newer Pi words a category differently.
    public enum Band: Int, Sendable, Comparable {
        case good, moderate, sensitive, unhealthy, veryUnhealthy, hazardous

        public static func < (a: Band, b: Band) -> Bool { a.rawValue < b.rawValue }
    }

    /// The band's name, short enough for a badge: the EPA's own "Unhealthy for Sensitive
    /// Groups" does not fit beside the temperature.
    public var shortLabel: String {
        switch band {
        case .good: return "Good"
        case .moderate: return "Moderate"
        case .sensitive: return "Sensitive groups"
        case .unhealthy: return "Unhealthy"
        case .veryUnhealthy: return "Very unhealthy"
        case .hazardous: return "Hazardous"
        }
    }

    public var band: Band {
        switch aqi {
        case ..<51: return .good
        case ..<101: return .moderate
        case ..<151: return .sensitive
        case ..<201: return .unhealthy
        case ..<301: return .veryUnhealthy
        default: return .hazardous
        }
    }
}

extension CalendarEvent {
    /// The location's first non-blank line. Google writes a venue's name and full address on
    /// separate lines, and the name is what reads at TV distance.
    public var shortLocation: String? {
        location?
            .split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }
}
