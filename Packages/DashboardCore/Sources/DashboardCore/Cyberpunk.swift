import Foundation

/// The Cyberpunk layout's model: the dashboard as *Cyberpunk 2077*'s Journal, after IdleHoursTV's
/// `cyberpunk` theme. The calendar is the job list, the birthdays are contacts, and the headings
/// break out of hex as the menu boots. Cyberpunk has no Pi theme behind it.
public enum Cyberpunk {
    // MARK: The decrypt

    /// The glyphs a heading cycles through while it decrypts: the hex of a breach.
    public static let hex = Array("0123456789ABCDEF")

    /// When character *i* of *count* locks, as a fraction of the decrypt: left to right with a
    /// seeded jitter, every character locked by 1.
    static func lockAt(_ i: Int, of count: Int, seed: UInt64) -> Double {
        guard count > 1 else { return 0.5 }
        var rng = Mix(seed: seed &+ UInt64(i) &* 0x9E37_79B9)
        let jitter = Double(rng.next() % 1000) / 1000
        return 0.08 + 0.62 * Double(i) / Double(count - 1) + 0.26 * jitter
    }

    /// The heading part-way through decrypting: a character not yet locked shows a hex glyph
    /// that changes with *frame*; spaces and punctuation never scramble. At progress 1 it is the
    /// text itself, and it is always the text's length.
    public static func decrypt(_ text: String, progress: Double, seed: UInt64, frame: Int) -> String {
        if progress >= 1 { return text }
        let chars = Array(text)
        return String(chars.enumerated().map { i, c in
            guard c.isLetter || c.isNumber, progress < lockAt(i, of: chars.count, seed: seed) else { return c }
            var rng = Mix(seed: seed ^ (UInt64(i) << 20) ^ UInt64(frame))
            return hex[Int(rng.next() % UInt64(hex.count))]
        })
    }

    /// A stable seed for a heading, so it breaks out of the same hex each time it boots.
    public static func seed(_ text: String) -> UInt64 {
        text.unicodeScalars.reduce(0xCBF2_9CE4_8422_2325) { ($0 ^ UInt64($1.value)) &* 0x100_0000_01B3 }
    }

    // MARK: Night City

    /// Night City's districts, a four-hour watch each, the small hours in Pacifica: where the
    /// screen says it is when the weather names no place.
    public static let districts = ["PACIFICA", "SANTO DOMINGO", "CITY CENTER", "WESTBROOK", "HEYWOOD", "WATSON"]

    public static func district(hour24: Int) -> String { districts[max(0, min(23, hour24)) / 4] }

    // MARK: The jobs

    /// A row of the job list: an event, and where it stands.
    public struct Job: Sendable, Equatable, Hashable {
        public enum State: Sendable, Equatable, Hashable {
            /// Under way now.
            case active
            /// The next to start, today or tomorrow: the tracked job.
            case tracked
            /// Later today.
            case upcoming
            /// Tomorrow.
            case tomorrow
            /// All day today.
            case allDay
        }

        public var event: CalendarEvent
        public var state: State
    }

    /// Today's all-day events, then the timed events still to finish today and tomorrow,
    /// soonest first, up to *limit* in all. The ones under way are active; the first after
    /// them is tracked. With room for only a few, the timed events come first and the all-day
    /// ones fill what is left, so a day of holidays never pushes the next meeting off.
    public static func jobs(_ snapshot: Snapshot, now: Date, limit: Int) -> [Job] {
        guard limit > 0 else { return [] }
        let zone = snapshot.timeZone
        let today = CivilDate(now, in: zone)
        let timed = Skylight.upNext(snapshot, now: now, limit: limit)
        var tracked = false
        let timedJobs = timed.map { event -> Job in
            if event.start <= now { return Job(event: event, state: .active) }
            if !tracked {
                tracked = true
                return Job(event: event, state: .tracked)
            }
            return Job(event: event, state: CivilDate(event.start, in: zone) == today ? .upcoming : .tomorrow)
        }
        let allDay = Skylight.allDay(snapshot, now: now)
            .prefix(max(0, limit - timedJobs.count))
            .map { Job(event: $0, state: .allDay) }
        return allDay + timedJobs
    }

    // MARK: The contacts

    /// The birthdays in the next fortnight, soonest first, up to *limit*.
    public static func contacts(_ snapshot: Snapshot, now: Date, limit: Int) -> [Birthday] {
        let horizon = CivilDate(now, in: snapshot.timeZone).adding(days: 13)
        return Array(Agenda.upcomingBirthdays(from: snapshot, now: now).filter { $0.date <= horizon }.prefix(limit))
    }

    // MARK: The gauges

    /// Where *value* sits between *low* and *high*, 0 to 1; the middle when they are one value.
    public static func fraction(_ value: Double, low: Double, high: Double) -> Double {
        guard high > low else { return 0.5 }
        return min(max((value - low) / (high - low), 0), 1)
    }

    /// How far through the daylight *now* is, 0 at sunrise and 1 at sunset; nil at night.
    public static func daylight(now: Date, rise: Date, set: Date) -> Double? {
        guard now >= rise, now <= set, set > rise else { return nil }
        return now.timeIntervalSince(rise) / set.timeIntervalSince(rise)
    }
}

/// SplitMix64, for the decrypt's glyphs.
private struct Mix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
