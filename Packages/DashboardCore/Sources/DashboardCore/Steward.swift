import Foundation

/// The Steward pair's model: two layouts meant for two displays side by side, in Seneschal's
/// HUD language. The wing holds now (the clock, the next thing, the sky); the main display holds
/// what is ahead, its centrepiece the next day as a strip running away from the wing, with the
/// events laid along it in lanes. These are the strip's window, its events and lanes, its
/// daylight, its hour labels, and the check line's word on the Pi's sources. Steward has no
/// Pi theme behind it.
public enum Steward {
    // MARK: The strip

    /// The strip's stretch of time: from an hour before now, for a day.
    public struct Window: Sendable, Equatable {
        public var start: Date
        public var hours: Double

        public init(now: Date, lead: Double = 1, hours: Double = 24) {
            start = now.addingTimeInterval(-lead * 3600)
            self.hours = hours
        }

        public var end: Date { start.addingTimeInterval(hours * 3600) }

        /// Where *date* falls along the strip, 0 at its start and 1 at its end; unclamped.
        public func fraction(_ date: Date) -> Double {
            date.timeIntervalSince(start) / (hours * 3600)
        }
    }

    /// An event on the strip: where it runs, clamped to the strip, and where it stands.
    public struct Span: Sendable, Equatable, Hashable {
        public enum State: Sendable, Equatable, Hashable {
            /// Under way now.
            case active
            /// The next to start.
            case next
            /// After that.
            case later
            /// Already over, in the hour the strip keeps behind now.
            case past
        }

        public var event: CalendarEvent
        public var start: Double
        public var end: Double
        public var state: State
    }

    /// The timed events overlapping *window*, soonest first, each clamped to it.
    public static func spans(_ snapshot: Snapshot, now: Date, window: Window) -> [Span] {
        var seenNext = false
        return (snapshot.sources.events?.data ?? [])
            .filter { !$0.isAllDay && $0.end > window.start && $0.start < window.end }
            .sorted { $0.start != $1.start ? $0.start < $1.start : $0.summary < $1.summary }
            .map { event in
                let state: Span.State
                if event.end <= now {
                    state = .past
                } else if event.start <= now {
                    state = .active
                } else if !seenNext {
                    seenNext = true
                    state = .next
                } else {
                    state = .later
                }
                return Span(event: event, start: max(window.fraction(event.start), 0),
                            end: min(window.fraction(event.end), 1), state: state)
            }
    }

    /// The lane each span takes, in order, so none overlaps another in its lane: the first lane
    /// free by the span's start. A span holds at least *minLength* of the strip, room for its
    /// label, so a short event still keeps the next clear of its name. Nil for a span with no
    /// lane free among *count*; the strip leaves it off.
    public static func lanes(_ spans: [(start: Double, end: Double)], minLength: Double, count: Int) -> [Int?] {
        var freeFrom = [Double](repeating: -.infinity, count: max(count, 0))
        return spans.map { span in
            guard let lane = freeFrom.firstIndex(where: { $0 <= span.start + 1e-9 }) else { return nil }
            freeFrom[lane] = max(span.end, span.start + minLength)
            return lane
        }
    }

    /// The stretches of *window* the sun is up, as fractions of it, from the rises and sets in
    /// order (`Skylight.sunTimes`). A stretch begun before the strip or running past it is cut
    /// at its edge; a set with no rise before it means the strip began in daylight.
    public static func daylight(_ sunTimes: [(time: Date, rise: Bool)], window: Window) -> [ClosedRange<Double>] {
        var stretches: [ClosedRange<Double>] = []
        var from: Double? = sunTimes.first.map { $0.rise ? nil : 0 } ?? nil
        for (time, rise) in sunTimes {
            let at = window.fraction(time)
            if rise {
                from = at
            } else if let start = from {
                stretches.append(start...at)
                from = nil
            }
        }
        if let start = from { stretches.append(start...1) }
        return stretches.compactMap { s in
            let lo = max(s.lowerBound, 0), hi = min(s.upperBound, 1)
            return hi > lo ? lo...hi : nil
        }
    }

    /// The whole hours of *zone* inside *window*, for its ticks and labels: on the zone's hour,
    /// which in a zone a half or three quarters off UTC isn't UTC's.
    public static func hours(in window: Window, zone: TimeZone) -> [Date] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        guard var hour = cal.nextDate(after: window.start.addingTimeInterval(-1), matching: DateComponents(minute: 0, second: 0),
                                      matchingPolicy: .nextTime) else { return [] }
        var out: [Date] = []
        while hour < window.end {
            out.append(hour)
            hour += 3600
        }
        return out
    }

    /// The temperature trace: the 24-hour ribbon (`Skylight.ribbon`) cut to *window*, which it
    /// runs a little past.
    public static func trace(_ weather: Weather, now: Date, window: Window) -> [Skylight.Point] {
        Skylight.ribbon(weather, now: now).filter { $0.time >= window.start && $0.time <= window.end }
    }

    /// The hours between the strip's labels: the fewest that leave *minSpacing* points between
    /// labels at *hourWidth* points an hour.
    public static func labelStep(hourWidth: Double, minSpacing: Double) -> Int {
        [1, 2, 3, 4, 6].first { Double($0) * hourWidth >= minSpacing } ?? 6
    }

    // MARK: The check line

    /// The sources the Pi sends that have gone stale, by the name the check line gives them,
    /// in a fixed order. Empty when everything is current: all as expected.
    public static func stale(_ sources: Sources) -> [String] {
        [("Calendar", sources.events?.staleness), ("Weather", sources.weather?.staleness),
         ("Birthdays", sources.birthdays?.staleness), ("Air", sources.airQuality?.staleness)]
            .compactMap { name, staleness in staleness?.isWorthFlagging == true ? name : nil }
    }
}
