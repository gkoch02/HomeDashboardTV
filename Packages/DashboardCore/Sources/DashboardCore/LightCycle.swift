import Foundation

/// The Pi's `light_cycle` theme as numbers: today on a 24-hour dial, midnight at the top.
///
/// Positions are clock hours, 0 to 24, in the dashboard's zone (`light_cycle_panel.py`'s
/// `_hours_of_day`). The sky comes from `SunModel`, so a Pi with coordinates gets its true
/// twilights and one without gets the panel's fallback arc.
public enum LightCycle {
    /// One timed event of today's, as an arc over its clock hours.
    public struct Span: Sendable, Equatable {
        public var event: CalendarEvent
        public var start: Double
        public var end: Double
        /// 0 is the outer lane; an event overlapping the last one there takes lane 1.
        public var lane: Int
    }

    /// The clock hour of *t* in *zone*: 13.5 for 1:30 pm.
    public static func hour(_ t: Date, in zone: TimeZone) -> Double {
        let c = Calendar.gregorian(zone).dateComponents([.hour, .minute, .second], from: t)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
    }

    /// Today's timed events as arcs, clipped to the day, at least ten minutes wide so a
    /// zero-length event still shows, and packed into two lanes as the panel packs them.
    public static func spans(_ events: [CalendarEvent], on day: CivilDate, zone: TimeZone) -> [Span] {
        let dayStart = day.start(in: zone)
        let dayEnd = day.adding(days: 1).start(in: zone)
        var laneEnd = [-1.0, -1.0]
        return events
            .filter { !$0.isAllDay && $0.start < dayEnd && $0.end > dayStart }
            .sorted { $0.start < $1.start }
            .map { event in
                let start = event.start <= dayStart ? 0 : hour(event.start, in: zone)
                let end = event.end >= dayEnd ? 24 : hour(event.end, in: zone)
                let span = (start, min(24, max(end, start + 1.0 / 6)))
                let lane = span.0 >= laneEnd[0] ? 0 : 1
                laneEnd[lane] = max(laneEnd[lane], span.1)
                return Span(event: event, start: span.0, end: span.1, lane: lane)
            }
    }

    /// The sun's altitude at every *stepMinutes* of the clock through *day*, 00:00 to 24:00,
    /// for colouring the dial's band. Samples sit on clock positions, not elapsed time, so on
    /// a daylight-saving day the band stays aligned with the dial's hours: a clock time the
    /// change skips reads the moment just after it, and one it repeats reads the first.
    public static func altitudes(_ sun: SunModel, on day: CivilDate, stepMinutes: Int = 10) -> [Double] {
        let n = 24 * 60 / stepMinutes
        return (0...n).map { sun.altitude(at: clockTime(minutes: $0 * stepMinutes, on: day, zone: sun.zone)) }
    }

    /// The moment *day*'s clock reads *minutes* past midnight; 24:00 is the next midnight.
    static func clockTime(minutes: Int, on day: CivilDate, zone: TimeZone) -> Date {
        guard minutes < 24 * 60 else { return day.adding(days: 1).start(in: zone) }
        let components = DateComponents(year: day.year, month: day.month, day: day.day,
                                        hour: minutes / 60, minute: minutes % 60)
        return Calendar.gregorian(zone).date(from: components) ?? day.start(in: zone)
    }

    /// Sunrise and sunset on *day*: where the altitude crosses the horizon (-0.833°, the
    /// refraction-corrected rim, as the Pi's `sun_times` uses). Nil for a day the sun never
    /// rises or never sets.
    public static func sunTimes(_ sun: SunModel, on day: CivilDate) -> (rise: Date, set: Date)? {
        let horizon = -0.833
        let start = day.start(in: sun.zone)
        let end = day.adding(days: 1).start(in: sun.zone)
        let step = 120.0
        var rise: Date?
        var set: Date?
        var t = start
        var previous = sun.altitude(at: t)
        while t < end {
            let next = t.addingTimeInterval(step)
            let alt = sun.altitude(at: next)
            if (previous < horizon) != (alt < horizon) {
                let f = (horizon - previous) / (alt - previous)
                let crossing = t.addingTimeInterval(step * f)
                if alt > previous { rise = rise ?? crossing } else { set = crossing }
            }
            previous = alt
            t = next
        }
        guard let rise, let set, set > rise else { return nil }
        return (rise, set)
    }

    /// Today's sunrise and sunset, as the panel resolves them: from the Pi's altitudes when it
    /// has coordinates and they cover the day, so the times agree with the band's colours,
    /// else the weather's.
    public static func daylight(_ snapshot: Snapshot, sun: SunModel, on day: CivilDate) -> (rise: Date, set: Date)? {
        if sun.isExact(from: day, through: day) { return sunTimes(sun, on: day) }
        let zone = snapshot.timeZone
        guard let rise = snapshot.sources.weather?.data?.sunrise, let set = snapshot.sources.weather?.data?.sunset,
              CivilDate(rise, in: zone) == day, CivilDate(set, in: zone) == day, set > rise else { return nil }
        return (rise, set)
    }

    /// Tomorrow's daylight minus today's, from the Pi's altitudes. Nil unless they cover both
    /// days: the fallback arc has the same day every day, which would read as no change.
    public static func dayLengthChange(_ sun: SunModel, from day: CivilDate) -> TimeInterval? {
        guard sun.isExact(from: day, through: day.adding(days: 1)),
              let today = sunTimes(sun, on: day),
              let tomorrow = sunTimes(sun, on: day.adding(days: 1)) else { return nil }
        return tomorrow.set.timeIntervalSince(tomorrow.rise) - today.set.timeIntervalSince(today.rise)
    }

    /// "+1m 52s", "−2m 05s": a day-length change, as the panel writes it.
    public static func formatChange(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        let sign = s >= 0 ? "+" : "−"
        return String(format: "%@%dm %02ds", sign, abs(s) / 60, abs(s) % 60)
    }

    /// "12h 54m".
    public static func formatLength(_ seconds: TimeInterval) -> String {
        let m = Int((seconds / 60).rounded())
        return String(format: "%dh %02dm", m / 60, m % 60)
    }
}
