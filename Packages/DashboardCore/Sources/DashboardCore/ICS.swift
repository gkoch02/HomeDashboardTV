import Foundation

/// Calendar events from an iCalendar feed (RFC 5545): what the Pi's `calendar_ical` reads with
/// `icalendar` and `recurring_ical_events`, for the Mac screensaver's "This Mac" source, which
/// can reach a feed's URL but not the Mac's calendars.
///
/// Recurring events are expanded in their own zone's wall-clock time, so a 9:00 standup stays
/// at 9:00 across a DST change, with EXDATE skipping an instance and RECURRENCE-ID moving one.
/// Rules repeat daily, weekly, monthly or yearly, with INTERVAL, COUNT, UNTIL, BYDAY (ordinals
/// too), BYMONTHDAY, BYMONTH and BYSETPOS; a rule finer than daily, or one this cannot read,
/// leaves just the first instance. Unlike the Pi, a cancelled event or instance is left out.
public enum ICS {
    public struct Feed: Sendable, Equatable {
        /// The feed's own name (`X-WR-CALNAME`), if it gives one.
        public var name: String?
        public var events: [CalendarEvent]
    }

    /// The Pi's cap on one series' instances in a window, against a runaway rule.
    static let maxPerSeries = 200

    /// The events of *text* that overlap *window*, sorted by start. *zone* is the dashboard's:
    /// what a floating time and an all-day date are read in. *fallbackName* names the
    /// calendar when the feed does not.
    public static func parse(_ text: String, zone: TimeZone, window: Range<Date>, fallbackName: String? = nil) -> Feed {
        let (name, raws) = components(of: text)
        let calendar = name ?? fallbackName

        // Instances an override moved or cancelled, by series.
        var replaced: [String: Set<Date>] = [:]
        for raw in raws {
            guard let uid = raw.uid, let id = raw.recurrenceID.flatMap({ stamp($0, zone: zone) }) else { continue }
            replaced[uid, default: []].insert(id.instant)
        }

        var events: [CalendarEvent] = []
        for raw in raws where raw.status?.uppercased() != "CANCELLED" {
            guard let start = raw.start.flatMap({ stamp($0, zone: zone) }) else { continue }
            let length = raw.length(from: start, zone: zone)
            var starts: [Stamp] = [start]
            if raw.recurrenceID == nil, let rule = raw.rule.flatMap(Rule.init) {
                let skipped = Set(raw.exdates.flatMap { values($0) }.compactMap { stamp($0, zone: zone)?.instant })
                    .union(raw.uid.flatMap { replaced[$0] } ?? [])
                starts = rule.instances(from: start, in: window).filter { !skipped.contains($0.instant) }
            }
            var kept = 0
            for stamp in starts {
                let begin = stamp.instant
                let end = length.end(after: stamp)
                guard begin < window.upperBound, end > window.lowerBound else { continue }
                kept += 1
                if kept > maxPerSeries { break }
                events.append(CalendarEvent(
                    summary: raw.summary.map(unescape) ?? "(no title)",
                    start: begin,
                    end: end,
                    isAllDay: start.isAllDay,
                    location: raw.location.map(unescape).flatMap { $0.isEmpty ? nil : $0 },
                    calendarName: calendar
                ))
            }
        }
        events.sort { ($0.start, $0.summary) < ($1.start, $1.summary) }
        return Feed(name: name, events: events)
    }

    // MARK: Lines and components

    /// A property: its name, parameters and raw value.
    struct Property {
        var name: String
        var params: [String: String]
        var value: String
    }

    /// One VEVENT's properties that matter here.
    struct RawEvent {
        var uid: String?
        var summary: String?
        var location: String?
        var status: String?
        var start: Property?
        var end: Property?
        var duration: Property?
        var rule: Property?
        var exdates: [Property] = []
        var recurrenceID: Property?

        /// How long each instance lasts, from DTEND or DURATION, else the Pi's defaults: a day
        /// for an all-day event, an hour for a timed one.
        func length(from start: Stamp, zone: TimeZone) -> Length {
            let seconds: TimeInterval
            if let end = end.flatMap({ ICS.stamp($0, zone: zone) }) {
                if start.isAllDay { return .days(max(0, start.day.days(until: end.day))) }
                seconds = max(0, end.instant.timeIntervalSince(start.instant))
            } else if let duration = duration.flatMap({ ICS.duration($0.value) }) {
                seconds = duration
            } else {
                return start.isAllDay ? .days(1) : .seconds(3600)
            }
            return start.isAllDay ? .days(Int((seconds / 86_400).rounded())) : .seconds(seconds)
        }
    }

    /// An instance's length: whole days for an all-day event, so an instance across a DST
    /// change still ends at midnight, and real time for a timed one.
    enum Length {
        case days(Int)
        case seconds(TimeInterval)

        func end(after start: Stamp) -> Date {
            switch self {
            case .days(let n): return start.day.adding(days: n).start(in: start.zone)
            case .seconds(let s): return start.instant.addingTimeInterval(s)
            }
        }
    }

    /// The calendar's name and its events. Lines folded onto the next (which starts with a
    /// space or tab) are joined first; properties of a VALARM inside an event are not its own.
    static func components(of text: String) -> (name: String?, events: [RawEvent]) {
        let unfolded = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n ", with: "")
            .replacingOccurrences(of: "\n\t", with: "")
        var name: String?
        var events: [RawEvent] = []
        var current: RawEvent?
        var depth = 0  // components open inside the current event
        for line in unfolded.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let p = property(String(line)) else { continue }
            switch (p.name, p.value.uppercased()) {
            case ("BEGIN", "VEVENT") where current == nil:
                current = RawEvent()
                depth = 0
                continue
            case ("END", "VEVENT") where depth == 0:
                if let c = current { events.append(c) }
                current = nil
                continue
            case ("BEGIN", _) where current != nil:
                depth += 1
                continue
            case ("END", _) where current != nil:
                depth -= 1
                continue
            default:
                break
            }
            guard current != nil else {
                if p.name == "X-WR-CALNAME", !p.value.isEmpty { name = unescape(p.value) }
                continue
            }
            guard depth == 0 else { continue }
            switch p.name {
            case "UID": current?.uid = p.value
            case "SUMMARY": current?.summary = p.value
            case "LOCATION": current?.location = p.value
            case "STATUS": current?.status = p.value
            case "DTSTART": current?.start = p
            case "DTEND": current?.end = p
            case "DURATION": current?.duration = p
            case "RRULE": current?.rule = p
            case "EXDATE": current?.exdates.append(p)
            case "RECURRENCE-ID": current?.recurrenceID = p
            default: break
            }
        }
        return (name, events)
    }

    /// `NAME;PARAM=VALUE;…:value`, with quoted parameter values left whole.
    static func property(_ line: String) -> Property? {
        var inQuotes = false
        var colon: String.Index?
        for i in line.indices {
            let c = line[i]
            if c == "\"" { inQuotes.toggle() }
            if c == ":", !inQuotes { colon = i; break }
        }
        guard let colon else { return nil }
        let head = line[..<colon].split(separator: ";", omittingEmptySubsequences: false)
        guard let first = head.first else { return nil }
        var params: [String: String] = [:]
        for part in head.dropFirst() {
            let kv = part.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            params[kv[0].uppercased()] = kv[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return Property(name: first.uppercased(), params: params, value: String(line[line.index(after: colon)...]))
    }

    /// A text value with its escapes undone: `\n`, `\,`, `\;` and `\\`.
    static func unescape(_ value: String) -> String {
        var out = ""
        var escaped = false
        for c in value {
            if escaped {
                out.append(c == "n" || c == "N" ? "\n" : c)
                escaped = false
            } else if c == "\\" {
                escaped = true
            } else {
                out.append(c)
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// Each of a property's comma-separated values as a property of its own (EXDATE lists).
    static func values(_ p: Property) -> [Property] {
        p.value.split(separator: ",").map { Property(name: p.name, params: p.params, value: String($0)) }
    }

    // MARK: Times

    /// A start or end: the day, the time of day in seconds (0 for a date), and the zone its
    /// wall-clock time is in, from which a recurrence's later instances are made.
    struct Stamp {
        var day: CivilDate
        var seconds: Int
        var zone: TimeZone
        var isAllDay: Bool

        var instant: Date { at(day) }

        /// The same time of day on *other*, in this stamp's zone.
        func at(_ other: CivilDate) -> Date {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = zone
            let c = DateComponents(year: other.year, month: other.month, day: other.day,
                                   hour: seconds / 3600, minute: seconds / 60 % 60, second: seconds % 60)
            return cal.date(from: c) ?? other.start(in: zone)
        }
    }

    /// A DATE (`20261031`), UTC DATE-TIME (`…T150000Z`), DATE-TIME in a TZID, or floating one.
    static func stamp(_ p: Property, zone: TimeZone) -> Stamp? {
        let v = p.value.trimmingCharacters(in: .whitespaces)
        let digits = v.filter(\.isNumber)
        guard digits.count >= 8, let y = Int(digits.prefix(4)), let m = Int(digits.dropFirst(4).prefix(2)),
              let d = Int(digits.dropFirst(6).prefix(2)) else { return nil }
        let day = CivilDate(year: y, month: m, day: d)
        guard v.contains("T") else { return Stamp(day: day, seconds: 0, zone: zone, isAllDay: true) }
        guard digits.count >= 14, let h = Int(digits.dropFirst(8).prefix(2)), let mi = Int(digits.dropFirst(10).prefix(2)),
              let s = Int(digits.dropFirst(12).prefix(2)) else { return nil }
        let own: TimeZone
        if v.hasSuffix("Z") {
            own = TimeZone(identifier: "UTC")!
        } else if let tzid = p.params["TZID"] {
            own = timeZone(tzid) ?? zone
        } else {
            own = zone
        }
        return Stamp(day: day, seconds: h * 3600 + mi * 60 + s, zone: own, isAllDay: false)
    }

    /// An IANA zone for a TZID: the name itself, the end of a path-like one
    /// (`/mozilla.org/20050126_1/America/New_York`), or Outlook's Windows names.
    static func timeZone(_ tzid: String) -> TimeZone? {
        if let z = TimeZone(identifier: tzid) { return z }
        let parts = tzid.split(separator: "/")
        for i in parts.indices {
            if let z = TimeZone(identifier: parts[i...].joined(separator: "/")) { return z }
        }
        return windowsZones[tzid].flatMap(TimeZone.init(identifier:))
    }

    private static let windowsZones = [
        "Eastern Standard Time": "America/New_York",
        "Central Standard Time": "America/Chicago",
        "Mountain Standard Time": "America/Denver",
        "US Mountain Standard Time": "America/Phoenix",
        "Pacific Standard Time": "America/Los_Angeles",
        "Alaskan Standard Time": "America/Anchorage",
        "Hawaiian Standard Time": "Pacific/Honolulu",
        "Atlantic Standard Time": "America/Halifax",
        "GMT Standard Time": "Europe/London",
        "Greenwich Standard Time": "Atlantic/Reykjavik",
        "W. Europe Standard Time": "Europe/Berlin",
        "Romance Standard Time": "Europe/Paris",
        "Central Europe Standard Time": "Europe/Budapest",
        "Central European Standard Time": "Europe/Warsaw",
        "E. Europe Standard Time": "Europe/Chisinau",
        "FLE Standard Time": "Europe/Kiev",
        "India Standard Time": "Asia/Kolkata",
        "China Standard Time": "Asia/Shanghai",
        "Tokyo Standard Time": "Asia/Tokyo",
        "AUS Eastern Standard Time": "Australia/Sydney",
        "New Zealand Standard Time": "Pacific/Auckland",
        "UTC": "UTC",
    ]

    /// `P1W`, `PT45M`, `P1DT2H`, `-PT15M`, in seconds.
    static func duration(_ value: String) -> TimeInterval? {
        var v = Substring(value.trimmingCharacters(in: .whitespaces).uppercased())
        var sign = 1.0
        if v.first == "-" { sign = -1; v = v.dropFirst() } else if v.first == "+" { v = v.dropFirst() }
        guard v.first == "P" else { return nil }
        var total = 0.0
        var number = ""
        var inTime = false
        var parts = 0
        for c in v.dropFirst() {
            if c.isNumber { number.append(c); continue }
            if c == "T" { inTime = true; continue }
            guard let n = Double(number) else { return nil }
            number = ""
            parts += 1
            switch (c, inTime) {
            case ("W", false): total += n * 604_800
            case ("D", false): total += n * 86_400
            case ("H", true): total += n * 3600
            case ("M", true): total += n * 60
            case ("S", true): total += n
            default: return nil
            }
        }
        return number.isEmpty && parts > 0 ? sign * total : nil
    }

    // MARK: Recurrence

    struct Rule {
        enum Frequency: String { case daily = "DAILY", weekly = "WEEKLY", monthly = "MONTHLY", yearly = "YEARLY" }

        var frequency: Frequency
        var interval = 1
        var count: Int?
        var until: Property?
        /// (ordinal, weekday 1 Sunday … 7 Saturday); ordinal 0 is every one.
        var byDay: [(Int, Int)] = []
        var byMonthDay: [Int] = []
        var byMonth: [Int] = []
        var bySetPos: [Int] = []
        var weekStart = 2

        private static let weekdays = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]

        init?(_ p: Property) {
            var parts: [String: String] = [:]
            for part in p.value.split(separator: ";") {
                let kv = part.split(separator: "=", maxSplits: 1)
                if kv.count == 2 { parts[kv[0].uppercased()] = String(kv[1]).uppercased() }
            }
            guard let f = parts["FREQ"].flatMap(Frequency.init) else { return nil }
            frequency = f
            interval = max(1, parts["INTERVAL"].flatMap { Int($0) } ?? 1)
            count = parts["COUNT"].flatMap { Int($0) }
            until = parts["UNTIL"].map { Property(name: "UNTIL", params: [:], value: $0) }
            func ints(_ key: String) -> [Int] { parts[key]?.split(separator: ",").compactMap { Int($0) } ?? [] }
            byMonthDay = ints("BYMONTHDAY")
            byMonth = ints("BYMONTH")
            bySetPos = ints("BYSETPOS")
            byDay = parts["BYDAY"]?.split(separator: ",").compactMap { item in
                guard let wd = Self.weekdays[String(item.suffix(2))] else { return nil }
                let ord = item.dropLast(2)
                return (ord.isEmpty ? 0 : Int(ord) ?? 0, wd)
            } ?? []
            weekStart = parts["WKST"].flatMap { Self.weekdays[$0] } ?? 2
        }

        /// The instances from *start* (the first, always) to before the end of *window*, within
        /// COUNT and UNTIL, in the start's wall-clock time. Without a COUNT to keep, the periods
        /// long before the window are skipped, so an old daily rule costs no more than a new one.
        func instances(from start: Stamp, in window: Range<Date>) -> [Stamp] {
            let limit = window.upperBound
            let lastDay: CivilDate? = until.flatMap { ICS.stamp($0, zone: start.zone) }.map { u in
                u.isAllDay ? u.day : CivilDate(u.instant, in: start.zone)
            }
            let untilInstant = until.flatMap { ICS.stamp($0, zone: start.zone) }.flatMap { $0.isAllDay ? nil : $0.instant }
            var out: [Stamp] = []
            var made = 0
            var skip = 0
            if count == nil {
                // Periods surely over a week before the window, at their longest.
                let longest = [Frequency.daily: 1, .weekly: 7, .monthly: 31, .yearly: 366][frequency]!
                let behind = start.day.days(until: CivilDate(window.lowerBound, in: start.zone)) - 7
                skip = max(0, behind / (longest * interval))
            }
            for period in skip..<(skip + 5000) {
                let days = candidates(period: period * interval, start: start.day)
                let ordered = applySetPos(days.sorted())
                for day in ordered where day >= start.day {
                    var s = start
                    s.day = day
                    let instant = s.instant
                    if let untilInstant, !start.isAllDay, instant > untilInstant { return out }
                    if let lastDay, start.isAllDay || untilInstant == nil, day > lastDay { return out }
                    made += 1
                    if let count, made > count { return out }
                    if instant >= limit { return out }
                    out.append(s)
                }
                if periodStart(period * interval, start: start.day).start(in: start.zone) >= limit { return out }
            }
            return out
        }

        private func applySetPos(_ days: [CivilDate]) -> [CivilDate] {
            guard !bySetPos.isEmpty, !days.isEmpty else { return days }
            return bySetPos.compactMap { pos -> CivilDate? in
                let i = pos > 0 ? pos - 1 : days.count + pos
                return days.indices.contains(i) ? days[i] : nil
            }.sorted()
        }

        /// The first day of the period *offset* periods after the start's.
        private func periodStart(_ offset: Int, start: CivilDate) -> CivilDate {
            switch frequency {
            case .daily: return start.adding(days: offset)
            case .weekly: return weekStartDay(of: start).adding(days: 7 * offset)
            case .monthly:
                let months = start.year * 12 + (start.month - 1) + offset
                return CivilDate(year: months / 12, month: months % 12 + 1, day: 1)
            case .yearly: return CivilDate(year: start.year + offset, month: 1, day: 1)
            }
        }

        private func weekStartDay(of day: CivilDate) -> CivilDate {
            day.adding(days: -((weekday(day) - weekStart + 7) % 7))
        }

        private func candidates(period offset: Int, start: CivilDate) -> [CivilDate] {
            let first = periodStart(offset, start: start)
            var days: [CivilDate]
            switch frequency {
            case .daily:
                days = [first]
                if !byDay.isEmpty { days = days.filter { d in byDay.contains { $0.1 == weekday(d) } } }
                if !byMonthDay.isEmpty { days = days.filter { matchesMonthDay($0) } }
            case .weekly:
                let wanted = byDay.isEmpty ? [weekday(start)] : byDay.map(\.1)
                days = (0..<7).map { first.adding(days: $0) }.filter { wanted.contains(weekday($0)) }
            case .monthly:
                days = monthDays(year: first.year, month: first.month, defaultDay: start.day)
            case .yearly:
                if !byMonth.isEmpty || !byMonthDay.isEmpty || byDay.isEmpty {
                    let months = byMonth.isEmpty ? (byMonthDay.isEmpty ? [start.month] : Array(1...12)) : byMonth
                    days = months.flatMap { monthDays(year: first.year, month: $0, defaultDay: start.day) }
                } else {
                    days = weekdays(in: (1...12).flatMap { allDays(year: first.year, month: $0) })
                }
            }
            if !byMonth.isEmpty { days = days.filter { byMonth.contains($0.month) } }
            return days
        }

        /// A month's days by BYMONTHDAY and BYDAY (both: those in both), else *defaultDay*.
        private func monthDays(year: Int, month: Int, defaultDay: Int) -> [CivilDate] {
            let all = allDays(year: year, month: month)
            switch (byMonthDay.isEmpty, byDay.isEmpty) {
            case (true, true):
                return defaultDay <= all.count ? [all[defaultDay - 1]] : []
            case (false, true):
                return all.filter { matchesMonthDay($0) }
            case (true, false):
                return weekdays(in: all)
            case (false, false):
                return weekdays(in: all).filter { matchesMonthDay($0) }
            }
        }

        /// The days of *span* BYDAY picks: every such weekday, or the nth (from the end when
        /// negative).
        private func weekdays(in span: [CivilDate]) -> [CivilDate] {
            var out = Set<CivilDate>()
            for (ordinal, wd) in byDay {
                let matching = span.filter { weekday($0) == wd }
                if ordinal == 0 {
                    out.formUnion(matching)
                } else {
                    let i = ordinal > 0 ? ordinal - 1 : matching.count + ordinal
                    if matching.indices.contains(i) { out.insert(matching[i]) }
                }
            }
            return Array(out)
        }

        private func matchesMonthDay(_ d: CivilDate) -> Bool {
            let length = daysIn(year: d.year, month: d.month)
            return byMonthDay.contains { $0 > 0 ? $0 == d.day : length + 1 + $0 == d.day }
        }

        private func allDays(year: Int, month: Int) -> [CivilDate] {
            (1...daysIn(year: year, month: month)).map { CivilDate(year: year, month: month, day: $0) }
        }

        private func daysIn(year: Int, month: Int) -> Int {
            switch month {
            case 2: return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28
            case 4, 6, 9, 11: return 30
            default: return 31
            }
        }

        private func weekday(_ d: CivilDate) -> Int {
            // 1970-01-01 was a Thursday (5).
            let epoch = CivilDate(year: 1970, month: 1, day: 1)
            return ((epoch.days(until: d) % 7 + 7) % 7 + 4) % 7 + 1
        }
    }
}
