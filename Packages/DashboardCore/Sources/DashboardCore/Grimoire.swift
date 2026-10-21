import Foundation

/// The Grimoire layout's model: the dashboard as an adventurer's tome, after the quest logs
/// and spellbooks of *Warcraft* and the tabletop. The calendar is the quest log, birthdays are
/// feast days, the weather is the day's augury, the air is the dragon's breath, and each of the
/// Pi's sources burns as a candle while its data is current. Grimoire has no Pi theme behind it.
public enum Grimoire {
    // MARK: The watch

    /// The watch of the day the hour falls in, by the sun: "Dawn" an hour either side of
    /// sunrise, "High Noon" an hour either side of the sun's midday, "Dusk" round sunset,
    /// "The Witching Hour" from eleven to one. *rise* and *set* are clock hours in the zone;
    /// without them, half past six and half past six.
    public static func watch(hour: Double, rise: Double? = nil, set: Double? = nil) -> String {
        let r = rise ?? 6.5, s = max(set ?? 18.5, (rise ?? 6.5) + 2)
        let noon = (r + s) / 2
        switch hour {
        case ..<1: return "The Witching Hour"
        case ..<(r - 1): return "The Small Hours"
        case ..<(r + 1): return "Dawn"
        case ..<(noon - 1): return "Morning"
        case ..<(noon + 1): return "High Noon"
        case ..<(s - 1): return "Afternoon"
        case ..<(s + 1): return "Dusk"
        case ..<22: return "Evening"
        case ..<23: return "Nightfall"
        default: return "The Witching Hour"
        }
    }

    /// The watch now, from the weather's sunrise and sunset when it has them.
    public static func watch(_ snapshot: Snapshot, now: Date) -> String {
        let zone = snapshot.timeZone
        let weather = snapshot.sources.weather?.data
        return watch(hour: LightCycle.hour(now, in: zone),
                     rise: weather?.sunrise.map { LightCycle.hour($0, in: zone) },
                     set: weather?.sunset.map { LightCycle.hour($0, in: zone) })
    }

    /// The date as a chronicle writes it: "Monday, the 20th of October".
    public static func dateLine(_ now: Date, zone: TimeZone, locale: Locale = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        cal.locale = locale
        let day = cal.component(.day, from: now)
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        formatter.locale = locale
        let ordinal = formatter.string(from: NSNumber(value: day)) ?? "\(day)"
        let style = Date.FormatStyle(locale: locale, timeZone: zone)
        return "\(now.formatted(style.weekday(.wide))), the \(ordinal) of \(now.formatted(style.month(.wide)))"
    }

    // MARK: The quest log

    /// A quest in the log: an event, and where it stands.
    public struct Quest: Sendable, Equatable, Hashable {
        public enum State: Sendable, Equatable, Hashable {
            /// Under way now.
            case underway
            /// The next to begin, today or tomorrow: the tracked quest.
            case next
            /// Later today.
            case today
            /// Tomorrow.
            case tomorrow
            /// All day today: a daily.
            case daily
        }

        public var event: CalendarEvent
        public var state: State
    }

    /// Today's dailies, then the timed events still to finish today and tomorrow, soonest
    /// first, up to *limit* in all. The ones under way lead; the first after them is next.
    /// With room for only a few, the timed events come first and the dailies fill what is
    /// left, so a week-long conference never pushes tonight's dinner off the page.
    public static func quests(_ snapshot: Snapshot, now: Date, limit: Int) -> [Quest] {
        guard limit > 0 else { return [] }
        let zone = snapshot.timeZone
        let today = CivilDate(now, in: zone)
        var next = false
        let timed = Skylight.upNext(snapshot, now: now, limit: limit).map { event -> Quest in
            if event.start <= now { return Quest(event: event, state: .underway) }
            if !next {
                next = true
                return Quest(event: event, state: .next)
            }
            return Quest(event: event, state: CivilDate(event.start, in: zone) == today ? .today : .tomorrow)
        }
        let dailies = Skylight.allDay(snapshot, now: now)
            .prefix(max(0, limit - timed.count))
            .map { Quest(event: $0, state: .daily) }
        return dailies + timed
    }

    // MARK: Feast days

    /// A birthday as a feast day: whose, and how many days off.
    public struct Feast: Sendable, Equatable, Hashable {
        public var birthday: Birthday
        public var daysAway: Int
    }

    /// The birthdays within the next *days*, soonest first, up to *limit*.
    public static func feasts(_ snapshot: Snapshot, now: Date, days: Int = 30, limit: Int) -> [Feast] {
        let zone = snapshot.timeZone
        let today = CivilDate(now, in: zone)
        let horizon = today.adding(days: days)
        return Agenda.upcomingBirthdays(from: snapshot, now: now)
            .filter { $0.date <= horizon }
            .prefix(limit)
            .map { Feast(birthday: $0, daysAway: Self.days(from: today, to: $0.date)) }
    }

    /// Whole days from one civil day to another.
    static func days(from a: CivilDate, to b: CivilDate) -> Int {
        let utc = TimeZone(identifier: "UTC")!
        return Int((b.start(in: utc).timeIntervalSince(a.start(in: utc)) / 86_400).rounded())
    }

    /// "Today", "Tomorrow", "In 5 days", else the weekday with the date.
    public static func feastWhen(_ feast: Feast, zone: TimeZone) -> String {
        switch feast.daysAway {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case ..<7: return "In \(feast.daysAway) days"
        default:
            return feast.birthday.date.start(in: zone)
                .formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated).day().month(.abbreviated))
        }
    }

    // MARK: The moon

    /// The moon's phase and how much of it shows: "Waxing Crescent, 14% lit".
    public static func moonLine(_ moon: Moon) -> String {
        guard let today = moon.today else { return moon.phaseName }
        return "\(moon.phaseName), \(Int(today.illumination.rounded()))% lit"
    }

    /// When the next full or new moon is: "Full moon in 12 days", "New moon tomorrow",
    /// "Full moon tonight".
    public static func nextMoon(_ moon: Moon) -> String {
        let name = moon.next.isFull ? "Full moon" : "New moon"
        switch moon.next.days {
        case ...0: return "\(name) tonight"
        case 1: return "\(name) tomorrow"
        default: return "\(name) in \(moon.next.days) days"
        }
    }

    // MARK: The dragon's breath

    /// The air's EPA band as the dragon's breath: sweet when good, deadly when hazardous.
    public static func breath(_ band: AirQuality.Band) -> String {
        switch band {
        case .good: return "Sweet"
        case .moderate: return "Fair"
        case .sensitive: return "Sour"
        case .unhealthy: return "Foul"
        case .veryUnhealthy: return "Noxious"
        case .hazardous: return "Deadly"
        }
    }

    // MARK: The candles

    /// How a source's candle burns: lit while its data is fresh, guttering as it ages, out once
    /// it is stale or expired, or the Pi cannot say.
    public enum Candle: Sendable, Equatable {
        case lit, guttering, out
    }

    public static func candle(_ staleness: Staleness) -> Candle {
        switch staleness {
        case .fresh: return .lit
        case .aging: return .guttering
        case .stale, .expired, .unknown: return .out
        }
    }

    /// A candle for each source the Pi sends, in the order they stand on the shelf.
    public static func candles(_ sources: Sources) -> [(name: String, candle: Candle)] {
        [
            ("Calendar", sources.events?.staleness),
            ("Weather", sources.weather?.staleness),
            ("Birthdays", sources.birthdays?.staleness),
            ("Air", sources.airQuality?.staleness),
        ].compactMap { name, staleness in staleness.map { (name, candle($0)) } }
    }
}
