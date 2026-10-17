import Foundation

/// The Uplink layout's model: a hologram terminal blended from IdleHoursTV's Deus Ex, Codex and
/// Cyberpunk themes. Its centrepiece is today as an orbit seen at a tilt, turning so that now is
/// always at the front; these are its turns, its nodes, the forecast's voice trace, the
/// narration's length and the uplink's signal. Uplink has no Pi theme behind it.
public enum Uplink {
    // MARK: The orbit

    /// Where *date* sits on the orbit, as a fraction of a turn from now: 0 at the front, a
    /// quarter turn six hours ahead, wrapped to [-0.5, 0.5) so twelve hours either way meet at
    /// the back.
    public static func turn(_ date: Date, now: Date) -> Double {
        let t = date.timeIntervalSince(now) / 86_400
        let wrapped = (t + 0.5).truncatingRemainder(dividingBy: 1)
        return (wrapped < 0 ? wrapped + 1 : wrapped) - 0.5
    }

    /// An event on the orbit: where it starts and ends, as turns from now. A start already past
    /// is clamped to now, so an event under way runs from the front.
    public struct Node: Sendable, Equatable, Hashable {
        public var event: CalendarEvent
        public var start: Double
        public var end: Double
        public var isActive: Bool
    }

    /// The timed events under way or starting within the next *hours*, soonest first. Each spans
    /// at least a few minutes of the orbit and never past the back of it.
    public static func nodes(_ snapshot: Snapshot, now: Date, hours: Double = 18) -> [Node] {
        (snapshot.sources.events?.data ?? [])
            .filter { !$0.isAllDay && $0.end > now && $0.start < now.addingTimeInterval(hours * 3600) }
            .sorted { $0.start != $1.start ? $0.start < $1.start : $0.summary < $1.summary }
            .map { event in
                let active = event.start <= now
                let start = active ? 0 : turn(event.start, now: now)
                let length = max(event.end.timeIntervalSince(max(event.start, now)) / 86_400, 0.006)
                return Node(event: event, start: start, end: min(start + length, 0.499), isActive: active)
            }
    }

    // MARK: The voice trace

    /// One bar of the forecast's voice trace: the temperature then, and the chance of rain.
    public struct Sample: Sendable, Equatable {
        public var temp: Double
        public var precip: Double
    }

    /// The next 24 hours as *count* evenly spaced samples, read off Skylight's ribbon (now, then
    /// the three-hour slots) by straight lines between its points; past its last point, its
    /// last. Empty with fewer than two points.
    public static func trace(_ weather: Weather, now: Date, count: Int) -> [Sample] {
        let points = Skylight.ribbon(weather, now: now)
        guard points.count >= 2, count > 0 else { return [] }
        return (0..<count).map { k in
            let at = now.addingTimeInterval(86_400 * Double(k) / Double(max(count - 1, 1)))
            guard let i = points.firstIndex(where: { $0.time >= at }) else {
                return Sample(temp: points.last!.temp, precip: points.last!.precipChance)
            }
            if i == 0 { return Sample(temp: points[0].temp, precip: points[0].precipChance) }
            let a = points[i - 1], b = points[i]
            let span = b.time.timeIntervalSince(a.time)
            let f = span > 0 ? at.timeIntervalSince(a.time) / span : 1
            return Sample(temp: a.temp + (b.temp - a.temp) * f,
                          precip: a.precipChance + (b.precipChance - a.precipChance) * f)
        }
    }

    // MARK: The narration

    /// How long the quote takes to read aloud, as the Codex's narrator does: 190 words a
    /// minute, four seconds at least and fourteen at most.
    public static func narration(words: Int) -> Double {
        min(max(Double(words) / 190 * 60, 4), 14)
    }

    /// How many of *words* the narrator has reached at *progress* (0 to 1) through the reading.
    public static func spoken(words: Int, progress: Double) -> Int {
        Int((Double(words) * min(max(progress, 0), 1)).rounded(.up))
    }

    // MARK: The signal

    /// The uplink's signal, as the stat bar's five pips: the share of the Pi's sources that are
    /// current (fresh or aging), of those it sends. None lit with no sources.
    public static func signal(_ sources: Sources) -> Int {
        let present = [sources.events?.staleness, sources.weather?.staleness,
                       sources.birthdays?.staleness, sources.airQuality?.staleness].compactMap { $0 }
        guard !present.isEmpty else { return 0 }
        let current = present.filter { $0 == .fresh || $0 == .aging }.count
        return Int((5 * Double(current) / Double(present.count)).rounded())
    }
}
