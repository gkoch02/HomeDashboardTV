import Foundation

/// The Skylight layout's model: the sky outside right now, as numbers a shader can paint, and
/// what goes in the text around it. Skylight has no Pi theme behind it; it is drawn for the TV.
///
/// The sky follows the sun's altitude (the Pi's samples, or the fallback arc), the current
/// weather (cloud, rain, snow, fog, thunder, wind) and the moon at tonight's phase.
public enum Skylight {
    /// What the sky holds at one moment.
    public struct Sky: Sendable, Equatable {
        /// The sun's altitude in degrees.
        public var altitude: Double
        /// Where the sun is across the sky, 0 at sunrise to 1 at sunset; outside that at night.
        public var sunPath: Double
        /// How much of the sky cloud covers, 0 to 1.
        public var cover: Double
        public var precip: SkyKind.Precip
        /// How hard it rains or snows, 0 to 1; 0 when dry.
        public var intensity: Double
        /// The wind's sideways push on the clouds and rain: negative blows left, positive right,
        /// at most 1 either way.
        public var drift: Double

        public var isNight: Bool { altitude < -6 }
        /// No sun or moon shows through the cloud.
        public var hidesBodies: Bool { cover >= 0.85 || intensity > 0 }
    }

    public static func sky(_ snapshot: Snapshot, now: Date) -> Sky {
        let sun = SunModel(snapshot: snapshot)
        let zone = snapshot.timeZone
        let weather = snapshot.sources.weather?.data
        let day = CivilDate(now, in: zone)
        let path: Double = {
            if let (rise, set) = LightCycle.daylight(snapshot, sun: sun, on: day) {
                return now.timeIntervalSince(rise) / set.timeIntervalSince(rise)
            }
            let hour = LightCycle.hour(now, in: zone)
            return (hour - sun.rise) / (sun.set - sun.rise)
        }()
        let kind = SkyKind(icon: weather?.currentIcon ?? "01d")
        let cover: Double = {
            switch (kind.level, kind.precip) {
            case (_, .rain), (_, .storm), (_, .snow): return 0.96
            case (_, .fog): return 0.25
            case (0, _): return 0.04
            case (1, _): return 0.32
            case (2, _): return 0.58
            default: return 0.86
            }
        }()
        let intensity: Double = {
            guard [.rain, .storm, .snow].contains(kind.precip) else { return 0 }
            let slot = weather.flatMap { nearestSlot($0.hourly, to: now) }
            return precipIntensity(mm: slot?.precipMm, showers: weather?.currentIcon.hasPrefix("09") == true)
        }()
        return Sky(
            altitude: sun.altitude(at: now),
            sunPath: path,
            cover: cover,
            precip: kind.precip,
            intensity: intensity,
            drift: drift(weather, isMetric: snapshot.isMetric)
        )
    }

    /// How hard it falls, from a 3-hour slot's total: a trace reads as light, 10 mm or more as
    /// a downpour. Without an amount, middling (heavier for showers, which come in bursts).
    static func precipIntensity(mm: Double?, showers: Bool) -> Double {
        guard let mm else { return showers ? 0.6 : 0.45 }
        return min(1, max(0.2, 0.2 + 0.8 * log1p(mm) / log1p(10)))
    }

    /// The wind's push across the screen: east blows right. `wind_deg` is where the wind comes
    /// from, so it blows toward the opposite bearing. A calm day still drifts a little, so
    /// the sky never stands still.
    static func drift(_ weather: Weather?, isMetric: Bool) -> Double {
        guard let weather, let deg = weather.windDeg else { return 0.2 }
        let speed = weather.windSpeed ?? 0
        let metresPerSecond = isMetric ? speed : speed * 0.44704
        let toward = (deg + 180) * .pi / 180
        let east = sin(toward)
        let strength = min(1, max(0.15, metresPerSecond / 10))
        let push = east * strength
        return abs(push) < 0.08 ? (push < 0 ? -0.08 : 0.08) : push
    }

    static func nearestSlot(_ hourly: [HourlyForecast], to now: Date) -> HourlyForecast? {
        hourly.min { abs($0.time.timeIntervalSince(now)) < abs($1.time.timeIntervalSince(now)) }
    }

    // MARK: The moon

    /// The moon's place in the sky now: `path` 0 at moonrise to 1 at moonset, and its phase.
    /// Nil while it is down, or when the snapshot cannot say.
    ///
    /// The Pi sends today's rise and set when it has coordinates. A set before the rise is
    /// this morning's, from the moon that rose yesterday: the moon is up from midnight until
    /// it, and again from the rise on. Without coordinates, the moon is taken to be up for
    /// about six hours either side of its transit (`Horizon.moonTransit`).
    public static func moon(_ snapshot: Snapshot, now: Date) -> (path: Double, fraction: Double)? {
        guard let moon = snapshot.moon else { return nil }
        let zone = snapshot.timeZone
        let day = CivilDate(now, in: zone)
        let fraction = moon.days.first { $0.date == day }?.fraction ?? moon.today?.fraction ?? 0
        /// About how long the moon stays up: half of a 24 h 50 m lunar day.
        let up = 12.42 * 3600
        if let rise = moon.rise, let set = moon.set {
            if set > rise {
                guard now >= rise && now <= set else { return nil }
                return (now.timeIntervalSince(rise) / set.timeIntervalSince(rise), fraction)
            }
            if now <= set {
                return (1 - set.timeIntervalSince(now) / up, fraction)
            }
            if now >= rise {
                return (now.timeIntervalSince(rise) / up, fraction)
            }
            return nil
        }
        for offset in [0, -1] {
            guard let transit = Horizon.moonTransit(on: day.adding(days: offset), moon: moon, zone: zone) else { continue }
            let path = 0.5 + now.timeIntervalSince(transit.time) / up
            if path >= 0 && path <= 1 { return (path, fraction) }
        }
        return nil
    }

    // MARK: The next 24 hours

    /// One point on the 24-hour ribbon.
    public struct Point: Sendable, Equatable {
        public var time: Date
        public var temp: Double
        public var icon: String
        public var precipChance: Double
        /// The first point: the weather now, not a forecast slot.
        public var isNow: Bool
    }

    /// The weather now, then each 3-hour slot that starts more than an hour from now, through
    /// a day ahead: nine points when the forecast reaches.
    public static func ribbon(_ weather: Weather, now: Date) -> [Point] {
        let first = Point(time: now, temp: weather.currentTemp, icon: weather.currentIcon,
                          precipChance: nearestSlot(weather.hourly, to: now)?.precipChance ?? 0, isNow: true)
        let ahead = weather.hourly
            .filter { $0.time > now.addingTimeInterval(3600) && $0.time <= now.addingTimeInterval(25 * 3600) }
            .sorted { $0.time < $1.time }
            .prefix(8)
            .map { Point(time: $0.time, temp: $0.temp, icon: $0.icon, precipChance: $0.precipChance ?? 0, isNow: false) }
        return [first] + ahead
    }

    /// Today's and tomorrow's sunrises and sunsets, as the Light Cycle resolves them (the Pi's
    /// altitudes when it has coordinates, else the weather's times), in order.
    public static func sunTimes(_ snapshot: Snapshot, now: Date) -> [(time: Date, rise: Bool)] {
        let sun = SunModel(snapshot: snapshot)
        let today = CivilDate(now, in: snapshot.timeZone)
        return [today, today.adding(days: 1)].flatMap { day -> [(time: Date, rise: Bool)] in
            guard let (rise, set) = LightCycle.daylight(snapshot, sun: sun, on: day) else { return [] }
            return [(rise, true), (set, false)]
        }
    }

    // MARK: The agenda

    /// Today's all-day events, by name.
    public static func allDay(_ snapshot: Snapshot, now: Date) -> [CalendarEvent] {
        Agenda.days(from: snapshot, now: now, count: 1)[0].events.filter(\.isAllDay)
    }

    /// The timed events still to finish, today and tomorrow, soonest first: the ones under way
    /// lead.
    public static func upNext(_ snapshot: Snapshot, now: Date, limit: Int) -> [CalendarEvent] {
        let zone = snapshot.timeZone
        let horizon = CivilDate(now, in: zone).adding(days: 2).start(in: zone)
        return (snapshot.sources.events?.data ?? [])
            .filter { !$0.isAllDay && $0.end > now && $0.start < horizon }
            .sorted { $0.start != $1.start ? $0.start < $1.start : $0.summary < $1.summary }
            .prefix(limit)
            .map { $0 }
    }

    /// When an upcoming event is, said for someone glancing at the screen: "Now", "In 25 min",
    /// "In 2 h", then the clock time; "Tomorrow" leads a time on the next day.
    public static func when(_ event: CalendarEvent, now: Date, zone: TimeZone) -> String {
        if event.start <= now { return "Now" }
        let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes < 60 { return "In \(minutes) min" }
        let today = CivilDate(now, in: zone)
        let time = CompactTime.string(event.start, in: zone)
        if CivilDate(event.start, in: zone) != today { return "Tomorrow \(time)" }
        if minutes < 180 {
            let hours = Double(minutes) / 60
            return hours.rounded() == hours ? "In \(Int(hours)) h" : String(format: "In %.1f h", hours)
        }
        return time
    }

    /// The days of the forecast from today on, up to *count*.
    public static func outlook(_ weather: Weather, now: Date, zone: TimeZone, count: Int) -> [DayForecast] {
        let today = CivilDate(now, in: zone)
        return Array(weather.forecast.filter { $0.date >= today }.sorted { $0.date < $1.date }.prefix(count))
    }
}
