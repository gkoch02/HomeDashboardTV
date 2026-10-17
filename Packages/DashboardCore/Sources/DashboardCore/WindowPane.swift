import Foundation

/// The Window layout's model: the weather as it shows on a pane of glass, and what the
/// lanterns beyond it stand for. Window has no Pi theme behind it; it is drawn for the TV.
public enum WindowPane {
    /// The pane and the view through it at one moment.
    public struct Glass: Sendable, Equatable {
        /// The sun's altitude in degrees: day, dusk or night beyond the glass.
        public var altitude: Double
        /// How much of the sky cloud covers, 0 to 1.
        public var cover: Double
        /// How wet the pane is, 0 to 1: how many beads sit on it and how many drops run down.
        /// A dry day leaves only a stray bead or two.
        public var wet: Double
        /// Snow caught on the pane, 0 to 1.
        public var snow: Double
        /// Frost creeping in from the edges, 0 to 1, as the temperature drops below freezing.
        public var frost: Double
        /// Mist on the glass, 0 to 1: fog outside, or air near saturation.
        public var mist: Double
        /// The wind's push on the running drops: negative leans them left, at most 1 either way.
        public var drift: Double
        public var storm: Bool
    }

    public static func glass(_ snapshot: Snapshot, now: Date) -> Glass {
        let sky = Skylight.sky(snapshot, now: now)
        let weather = snapshot.sources.weather?.data
        let celsius = weather.map { snapshot.isMetric ? $0.currentTemp : ($0.currentTemp - 32) * 5 / 9 }
        return Glass(
            altitude: sky.altitude,
            cover: sky.cover,
            wet: wetness(raining: sky.precip == .rain || sky.precip == .storm, intensity: sky.intensity),
            snow: sky.precip == .snow ? 0.4 + 0.6 * sky.intensity : 0,
            frost: celsius.map(frost(celsius:)) ?? 0,
            mist: mist(humidity: weather?.humidity, fog: sky.precip == .fog),
            drift: sky.drift,
            storm: sky.precip == .storm
        )
    }

    /// Rain wets the pane from a third for a drizzle to all of it for a downpour; dry, it is
    /// all but clear.
    static func wetness(raining: Bool, intensity: Double) -> Double {
        raining ? 0.35 + 0.65 * min(max(intensity, 0), 1) : 0.02
    }

    /// None above 1 °C, all of it by −5 °C.
    static func frost(celsius: Double) -> Double {
        let t = min(max((1 - celsius) / 6, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Fog outside mists the glass; so, more faintly, does air above 85 % humidity.
    static func mist(humidity: Int?, fog: Bool) -> Double {
        if fog { return 0.55 }
        return min(max((Double(humidity ?? 0) - 85) / 15, 0), 1) * 0.3
    }

    /// What the lanterns beyond the glass stand for, one each: the next three events still to
    /// finish, today and tomorrow, then the next birthday within the week.
    public static func lamps(_ snapshot: Snapshot, now: Date) -> (events: [CalendarEvent], birthday: Birthday?) {
        let today = CivilDate(now, in: snapshot.timeZone)
        let birthday = Agenda.upcomingBirthdays(from: snapshot, now: now).first { $0.date <= today.adding(days: 6) }
        return (Skylight.upNext(snapshot, now: now, limit: 3), birthday)
    }
}
