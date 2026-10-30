import Foundation

/// Weather, air quality and place search from Open-Meteo (open-meteo.com), which needs no key,
/// mapped onto the shapes the Pi sends so the layouts draw them unchanged. Where the Pi's
/// OpenWeatherMap differs, this follows the Pi: icons are OWM codes (`02d`), descriptions OWM's
/// lower-case words, and the hourly forecast OWM's 3-hour grid.
public enum OpenMeteo {
    public enum Failure: Error, Equatable, LocalizedError {
        case http(Int)
        case malformed

        public var errorDescription: String? {
            switch self {
            case .http(let code): return "Open-Meteo answered HTTP \(code)."
            case .malformed: return "Open-Meteo sent something unreadable."
            }
        }
    }

    // MARK: Requests

    public static func forecastURL(latitude: Double, longitude: Double, metric: Bool) -> URL {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(latitude)),
            .init(name: "longitude", value: String(longitude)),
            .init(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,pressure_msl,wind_speed_10m,wind_direction_10m,uv_index"),
            .init(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability,precipitation,is_day"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset"),
            .init(name: "temperature_unit", value: metric ? "celsius" : "fahrenheit"),
            // OWM's units: metres a second in metric, miles an hour in imperial.
            .init(name: "wind_speed_unit", value: metric ? "ms" : "mph"),
            .init(name: "timezone", value: "auto"),
            .init(name: "timeformat", value: "unixtime"),
            .init(name: "forecast_days", value: "7"),
        ]
        return c.url!
    }

    public static func airQualityURL(latitude: Double, longitude: Double) -> URL {
        var c = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        c.queryItems = [
            .init(name: "latitude", value: String(latitude)),
            .init(name: "longitude", value: String(longitude)),
            .init(name: "current", value: "us_aqi,pm2_5"),
            .init(name: "timeformat", value: "unixtime"),
        ]
        return c.url!
    }

    public static func searchURL(_ name: String) -> URL {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [.init(name: "name", value: name), .init(name: "count", value: "8")]
        return c.url!
    }

    /// The body of *url*, refusing anything but a 200.
    public static func get(_ url: URL, session: URLSession = .shared) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw Failure.http(http.statusCode) }
        return data
    }

    // MARK: Forecast

    private struct ForecastResponse: Decodable {
        var utcOffsetSeconds: Int
        var current: Current
        var hourly: Hourly
        var daily: Daily

        enum CodingKeys: String, CodingKey {
            case current, hourly, daily, utcOffsetSeconds = "utc_offset_seconds"
        }

        struct Current: Decodable {
            var time: TimeInterval
            var temperature2m: Double
            var relativeHumidity2m: Double
            var apparentTemperature: Double?
            var isDay: Int
            var weatherCode: Int
            var pressureMsl: Double?
            var windSpeed10m: Double?
            var windDirection10m: Double?
            var uvIndex: Double?

            enum CodingKeys: String, CodingKey {
                case time, isDay = "is_day", weatherCode = "weather_code", pressureMsl = "pressure_msl", uvIndex = "uv_index"
                case temperature2m = "temperature_2m", relativeHumidity2m = "relative_humidity_2m"
                case apparentTemperature = "apparent_temperature", windSpeed10m = "wind_speed_10m"
                case windDirection10m = "wind_direction_10m"
            }
        }

        struct Hourly: Decodable {
            var time: [TimeInterval]
            var temperature2m: [Double?]
            var weatherCode: [Int?]
            var precipitationProbability: [Double?]
            var precipitation: [Double?]
            var isDay: [Int?]

            enum CodingKeys: String, CodingKey {
                case time, precipitation, temperature2m = "temperature_2m", weatherCode = "weather_code"
                case precipitationProbability = "precipitation_probability", isDay = "is_day"
            }
        }

        struct Daily: Decodable {
            var time: [TimeInterval]
            var weatherCode: [Int?]
            var temperature2mMax: [Double?]
            var temperature2mMin: [Double?]
            var precipitationProbabilityMax: [Double?]
            var sunrise: [TimeInterval?]
            var sunset: [TimeInterval?]

            enum CodingKeys: String, CodingKey {
                case time, sunrise, sunset, weatherCode = "weather_code"
                case temperature2mMax = "temperature_2m_max", temperature2mMin = "temperature_2m_min"
                case precipitationProbabilityMax = "precipitation_probability_max"
            }
        }
    }

    /// The forecast as the Pi's `Weather`, at *now*, in *zone* (the place's), named *place*.
    public static func weather(from data: Data, now: Date, zone: TimeZone, place: String?) throws -> Weather {
        let r: ForecastResponse
        do { r = try JSONDecoder().decode(ForecastResponse.self, from: data) } catch { throw Failure.malformed }
        let c = r.current
        let d = r.daily
        guard !d.time.isEmpty else { throw Failure.malformed }
        let today = CivilDate(now, in: zone)

        // A day's time is its midnight at today's offset, even past a DST change, so it is read
        // in that offset: after the fall back, the 2nd's midnight comes as the 1st's 11pm.
        let stamped = TimeZone(secondsFromGMT: r.utcOffsetSeconds) ?? zone
        func day(_ i: Int) -> CivilDate { CivilDate(Date(timeIntervalSince1970: d.time[i]), in: stamped) }
        let todayIndex = d.time.indices.first { day($0) == today } ?? 0

        var forecast: [DayForecast] = []
        for i in d.time.indices where day(i) > today {
            guard let high = d.temperature2mMax[i], let low = d.temperature2mMin[i], let code = d.weatherCode[i] else { continue }
            forecast.append(DayForecast(
                date: day(i), high: high, low: low,
                icon: icon(code, day: true), description: description(code),
                precipChance: d.precipitationProbabilityMax[i].map { $0 / 100 }
            ))
        }

        return Weather(
            currentTemp: c.temperature2m,
            currentIcon: icon(c.weatherCode, day: c.isDay != 0),
            currentDescription: description(c.weatherCode),
            high: d.temperature2mMax[todayIndex] ?? c.temperature2m,
            low: d.temperature2mMin[todayIndex] ?? c.temperature2m,
            humidity: Int(c.relativeHumidity2m.rounded()),
            pressure: c.pressureMsl,
            feelsLike: c.apparentTemperature,
            windSpeed: c.windSpeed10m,
            windDeg: c.windDirection10m,
            uvIndex: c.uvIndex,
            sunrise: d.sunrise[todayIndex].map(Date.init(timeIntervalSince1970:)),
            sunset: d.sunset[todayIndex].map(Date.init(timeIntervalSince1970:)),
            locationName: place,
            forecast: forecast,
            alerts: [],
            hourly: threeHourly(r.hourly, after: now)
        )
    }

    /// The hourly forecast on OWM's grid: a slot every 3 hours on the UTC hours divisible by
    /// 3, from the first after *now*, for five days (40 slots). A slot's precipitation is the
    /// sum over its three hours and its chance the highest of them.
    private static func threeHourly(_ h: ForecastResponse.Hourly, after now: Date) -> [HourlyForecast] {
        var slots: [HourlyForecast] = []
        for i in h.time.indices where h.time[i] > now.timeIntervalSince1970 && Int(h.time[i]) % (3 * 3600) == 0 {
            guard let temp = h.temperature2m[i], let code = h.weatherCode[i] else { continue }
            let span = i..<min(i + 3, h.time.count)
            let chances = span.compactMap { h.precipitationProbability[$0] }
            let mm = span.compactMap { h.precipitation[$0] }
            slots.append(HourlyForecast(
                time: Date(timeIntervalSince1970: h.time[i]),
                temp: temp,
                icon: icon(code, day: h.isDay[i].map { $0 != 0 } ?? true),
                precipChance: chances.max().map { $0 / 100 },
                precipMm: mm.isEmpty ? nil : mm.reduce(0, +)
            ))
            if slots.count == 40 { break }
        }
        return slots
    }

    // MARK: WMO codes

    /// The OWM icon code for a WMO weather code, with OWM's `d` or `n`.
    public static func icon(_ code: Int, day: Bool) -> String {
        let base: String
        switch code {
        case 0: base = "01"
        case 1: base = "02"
        case 2: base = "03"
        case 3: base = "04"
        case 45, 48: base = "50"
        case 51...57, 80...82: base = "09"
        case 66, 67, 71...77, 85, 86: base = "13"
        case 61...65: base = "10"
        case 95...99: base = "11"
        default: base = "03"
        }
        return base + (day ? "d" : "n")
    }

    /// A WMO weather code in OWM's words.
    public static func description(_ code: Int) -> String {
        switch code {
        case 0: return "clear sky"
        case 1: return "few clouds"
        case 2: return "scattered clouds"
        case 3: return "overcast clouds"
        case 45: return "fog"
        case 48: return "freezing fog"
        case 51: return "light drizzle"
        case 53: return "drizzle"
        case 55: return "heavy drizzle"
        case 56, 57: return "freezing drizzle"
        case 61: return "light rain"
        case 63: return "moderate rain"
        case 65: return "heavy rain"
        case 66, 67: return "freezing rain"
        case 71: return "light snow"
        case 73: return "snow"
        case 75: return "heavy snow"
        case 77: return "snow grains"
        case 80: return "light shower rain"
        case 81: return "shower rain"
        case 82: return "heavy shower rain"
        case 85: return "light shower snow"
        case 86: return "heavy shower snow"
        case 95: return "thunderstorm"
        case 96, 99: return "thunderstorm with hail"
        default: return "cloudy"
        }
    }

    // MARK: Air quality

    private struct AirResponse: Decodable {
        var current: Current
        struct Current: Decodable {
            var usAqi: Double?
            var pm25: Double?

            enum CodingKeys: String, CodingKey {
                case usAqi = "us_aqi"
                case pm25 = "pm2_5"
            }
        }
    }

    /// The air as the Pi's PurpleAir block: the US AQI, its EPA band's name and PM2.5.
    public static func airQuality(from data: Data) throws -> AirQuality {
        guard let r = try? JSONDecoder().decode(AirResponse.self, from: data), let aqi = r.current.usAqi else {
            throw Failure.malformed
        }
        let value = Int(aqi.rounded())
        return AirQuality(aqi: value, category: category(aqi: value), pm25: r.current.pm25 ?? 0)
    }

    /// The Pi's `_aqi_category`.
    static func category(aqi: Int) -> String {
        switch aqi {
        case ...50: return "Good"
        case ...100: return "Moderate"
        case ...150: return "Unhealthy for Sensitive Groups"
        case ...200: return "Unhealthy"
        case ...300: return "Very Unhealthy"
        default: return "Hazardous"
        }
    }

    // MARK: Places

    private struct SearchResponse: Decodable {
        var results: [Result]?
        struct Result: Decodable {
            var name: String
            var latitude: Double
            var longitude: Double
            var timezone: String?
            var admin1: String?
            var country: String?
        }
    }

    /// A place found by name, and how to tell it from others of the same name.
    public struct Found: Sendable, Equatable, Identifiable {
        public var place: LocalSnapshot.Place
        /// "New York, United States".
        public var detail: String
        public var id: String { "\(place.latitude),\(place.longitude)" }
    }

    public static func places(from data: Data) throws -> [Found] {
        guard let r = try? JSONDecoder().decode(SearchResponse.self, from: data) else { throw Failure.malformed }
        return (r.results ?? []).compactMap { p in
            guard let zone = p.timezone, TimeZone(identifier: zone) != nil else { return nil }
            let detail = [p.name, p.admin1, p.country].compactMap { $0 }.reduce(into: [String]()) { parts, part in
                if parts.last != part { parts.append(part) }
            }.joined(separator: ", ")
            return Found(place: .init(name: p.name, latitude: p.latitude, longitude: p.longitude, timezone: zone), detail: detail)
        }
    }
}
