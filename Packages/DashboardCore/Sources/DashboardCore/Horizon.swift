import Foundation

/// The Horizon layout's model: the Pi's `wide_horizon_panel` as data. The next 72 hours on one
/// time axis, with the sky, the forecast and the calendar placed on it. The view only paints.
///
/// Times are instants; the axis runs on real time, with each hour's width set by its local
/// clock hour, so a DST day simply has 23 or 25 hour columns.
public enum Horizon {
    public static let windowHours = 72
    public static let slotHours = 3
    static let wakeHour = 6
    static let sleepHour = 23
    /// A night hour (23:00 to 06:00) takes this share of a waking hour's width.
    static let nightWeight = 0.35

    /// The start of the 3-hour slot holding *now*: the window moves at most eight times a day.
    ///
    /// Set as a clock hour, not counted from midnight: on a DST day hours added to midnight
    /// are elapsed time, which put 03:30 on spring-forward day in a window starting at 04:00.
    public static func windowStart(now: Date, in zone: TimeZone) -> Date {
        let cal = Calendar.gregorian(zone)
        let hour = cal.component(.hour, from: now)
        return cal.date(bySettingHour: (hour / slotHours) * slotHours, minute: 0, second: 0, of: now) ?? now
    }

    static func hourWeight(_ hour: Int) -> Double {
        (wakeHour..<sleepHour).contains(hour) ? 1 : nightWeight
    }
}

extension Calendar {
    static func gregorian(_ zone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal
    }
}

// MARK: - The time axis

/// Piecewise-linear map between time and x over the window, a breakpoint on every hour.
public struct TimeAxis: Sendable, Equatable {
    public let start: Date
    public let hours: Int
    public let x0: Double
    public let x1: Double
    public let zone: TimeZone
    let xs: [Double]

    public var end: Date { start.addingTimeInterval(Double(hours) * 3600) }

    public init(start: Date, hours: Int = Horizon.windowHours, x0: Double, x1: Double, zone: TimeZone) {
        self.start = start
        self.hours = hours
        self.x0 = x0
        self.x1 = x1
        self.zone = zone
        let cal = Calendar.gregorian(zone)
        let weights = (0..<hours).map { k in
            Horizon.hourWeight(cal.component(.hour, from: start.addingTimeInterval(Double(k) * 3600)))
        }
        let scale = (x1 - x0) / weights.reduce(0, +)
        var xs = [x0]
        for w in weights { xs.append(xs[xs.count - 1] + w * scale) }
        self.xs = xs
    }

    /// x for *t*, clamped to the window.
    public func x(_ t: Date) -> Double {
        let h = t.timeIntervalSince(start) / 3600
        if h <= 0 { return x0 }
        if h >= Double(hours) { return x1 }
        let k = Int(h)
        return xs[k] + (h - Double(k)) * (xs[k + 1] - xs[k])
    }

    /// x for *t*, carried on past either end at the edge hour's width, so a curve through
    /// slots outside the window keeps its slope.
    public func xUnclamped(_ t: Date) -> Double {
        let h = t.timeIntervalSince(start) / 3600
        if h < 0 { return x0 + h * (xs[1] - xs[0]) }
        if h > Double(hours) { return x1 + (h - Double(hours)) * (xs[hours] - xs[hours - 1]) }
        return x(t)
    }

    /// The time at *x*: the inverse of `x(_:)`.
    public func time(atX x: Double) -> Date {
        if x <= xs[0] { return start }
        if x >= xs[hours] { return end }
        var lo = 0, hi = hours
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if xs[mid] <= x { lo = mid } else { hi = mid }
        }
        let frac = (x - xs[lo]) / (xs[lo + 1] - xs[lo])
        return start.addingTimeInterval((Double(lo) + frac) * 3600)
    }

    /// Each local midnight inside the window, with the day it starts.
    public var midnights: [(x: Double, day: CivilDate)] {
        var out: [(Double, CivilDate)] = []
        var day = CivilDate(start, in: zone).adding(days: 1)
        while day.start(in: zone) < end {
            out.append((x(day.start(in: zone)), day))
            day = day.adding(days: 1)
        }
        return out
    }

    /// Each day's slice of the window, left to right.
    public var dayColumns: [(x0: Double, x1: Double, day: CivilDate)] {
        let starts = [(x: x0, day: CivilDate(start, in: zone))] + midnights
        return starts.indices.map { i in
            (starts[i].x, i + 1 < starts.count ? starts[i + 1].x : x1, starts[i].day)
        }
    }

    /// The hours to label under the sky: 6a, 12p and 6p.
    public var labelledHours: [Date] {
        let cal = Calendar.gregorian(zone)
        return (0...hours).map { start.addingTimeInterval(Double($0) * 3600) }
            .filter { [6, 12, 18].contains(cal.component(.hour, from: $0)) && cal.component(.minute, from: $0) == 0 }
    }
}

// MARK: - The sun

/// Solar altitude across the window. From the Pi's `sun` block when it sends one (it has
/// coordinates): its samples, interpolated, and its solar noons. Otherwise the Pi's own
/// fallback (`altitude_fn`): an arc between the day's sunrise and sunset, a sine by day and
/// a linear fall at night, which puts the twilights where they are; without sun times,
/// 06:30 and 19:30.
public struct SunModel: Sendable, Equatable {
    /// Local clock hours, for the fallback arc.
    public let rise: Double
    public let set: Double
    public let zone: TimeZone
    public let sun: Sun?
    /// The fallback arc's height at noon, in degrees.
    static let peak = 50.0

    public init(weather: Weather?, sun: Sun? = nil, zone: TimeZone) {
        self.zone = zone
        self.sun = sun.flatMap { $0.altitudes.count >= 2 && $0.stepMinutes > 0 ? $0 : nil }
        let cal = Calendar.gregorian(zone)
        func clock(_ d: Date?) -> Double? {
            guard let d else { return nil }
            let c = cal.dateComponents([.hour, .minute], from: d)
            return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        }
        if let r = clock(weather?.sunrise), let s = clock(weather?.sunset), s > r {
            rise = r
            set = s
        } else {
            rise = 6.5
            set = 19.5
        }
    }

    public init(snapshot: Snapshot) {
        self.init(weather: snapshot.sources.weather?.data, sun: snapshot.sun, zone: snapshot.timeZone)
    }

    /// Whether the altitudes are the Pi's, not the fallback arc.
    public var isExact: Bool { sun != nil }

    /// Degrees above the horizon at *t*: the Pi's samples where they reach, else the arc.
    public func altitude(at t: Date) -> Double {
        if let sun {
            let k = t.timeIntervalSince(sun.start) / Double(sun.stepMinutes * 60)
            if k >= 0 && k <= Double(sun.altitudes.count - 1) {
                let i = min(Int(k), sun.altitudes.count - 2)
                let f = k - Double(i)
                return sun.altitudes[i] + (sun.altitudes[i + 1] - sun.altitudes[i]) * f
            }
        }
        return arcAltitude(at: t)
    }

    func arcAltitude(at t: Date) -> Double {
        let cal = Calendar.gregorian(zone)
        let c = cal.dateComponents([.hour, .minute, .second], from: t)
        let h = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
        if h >= rise && h <= set {
            return Self.peak * sin(.pi * (h - rise) / (set - rise))
        }
        let dist = h > set ? min(h - set, rise + 24 - h) : min(rise - h, h + 24 - set)
        return max(-40, -12 * dist)
    }

    /// Each solar noon inside the window with the sun up, with its altitude.
    public func noons(in axis: TimeAxis) -> [(time: Date, altitude: Double)] {
        if let sun {
            return sun.noons
                .filter { $0.time >= axis.start && $0.time <= axis.end && $0.altitude > 0 }
                .map { ($0.time, $0.altitude) }
        }
        var out: [(Date, Double)] = []
        var day = CivilDate(axis.start, in: zone)
        let last = CivilDate(axis.end, in: zone)
        while day <= last {
            let noon = day.start(in: zone).addingTimeInterval((rise + set) / 2 * 3600)
            if noon >= axis.start && noon <= axis.end {
                let alt = altitude(at: noon)
                if alt > 0 { out.append((noon, alt)) }
            }
            day = day.adding(days: 1)
        }
        return out
    }
}

// MARK: - The forecast

/// What an OWM icon puts in the sky.
public struct SkyKind: Sendable, Equatable {
    public enum Precip: Sendable, Equatable { case none, rain, storm, snow, fog }

    /// 0 clear, 1 a few clouds, 2 scattered, 3 overcast.
    public var level: Int
    public var precip: Precip

    public init(icon: String) {
        switch icon.prefix(2) {
        case "02": (level, precip) = (1, .none)
        case "03": (level, precip) = (2, .none)
        case "04": (level, precip) = (3, .none)
        case "09": (level, precip) = (3, .rain)
        case "10": (level, precip) = (2, .rain)
        case "11": (level, precip) = (3, .storm)
        case "13": (level, precip) = (3, .snow)
        case "50": (level, precip) = (1, .fog)
        default: (level, precip) = (0, .none)
        }
    }

    /// Overcast or wet: no sun or moon shows through it.
    public var hidesBodies: Bool { level >= 3 || [.rain, .storm, .snow].contains(precip) }
}

/// One 3-hour forecast slot on the axis.
public struct HorizonSlot: Sendable, Equatable {
    public var start: Date
    public var end: Date
    public var temp: Double
    public var icon: String
    public var precipChance: Double
    public var precipMm: Double?
    /// Filled in from the reading now, before the forecast's first slot (`lead_in`).
    public var isStandIn: Bool

    public var sky: SkyKind { SkyKind(icon: icon) }
}

public struct Extreme: Sendable, Equatable {
    public enum Kind: Sendable { case high, low }
    public var kind: Kind
    public var time: Date
    public var temp: Double
}

extension Horizon {
    /// The forecast slots touching the window, one either side kept so the curve reaches the
    /// edges, led in from the reading now. OWM's grid sits on UTC 3-hour boundaries and starts
    /// after the request, so the window's start is usually before the first slot; stand-ins
    /// carrying the current reading cover it.
    public static func slots(weather: Weather?, axis: TimeAxis) -> [HorizonSlot] {
        guard let weather else { return [] }
        let local = weather.hourly.sorted { $0.time < $1.time }
        let inside = local.indices.filter { local[$0].time >= axis.start && local[$0].time <= axis.end }
        guard let first = inside.first, let last = inside.last else { return [] }
        let picked = Array(local[max(0, first - 1)..<min(local.count, last + 2)])
        let nominal = TimeInterval(slotHours * 3600)

        var out = picked.indices.map { i -> HorizonSlot in
            let h = picked[i]
            var end = h.time.addingTimeInterval(nominal)
            if i + 1 < picked.count {
                let gap = picked[i + 1].time.timeIntervalSince(h.time)
                if abs(gap - nominal) <= 3600 { end = picked[i + 1].time }
            }
            return HorizonSlot(start: h.time, end: end, temp: h.temp, icon: h.icon,
                               precipChance: h.precipChance ?? 0, precipMm: h.precipMm, isStandIn: false)
        }
        var t = out[0].start
        var lead: [HorizonSlot] = []
        while t > axis.start {
            let s = t.addingTimeInterval(-nominal)
            lead.append(HorizonSlot(start: s, end: t, temp: weather.currentTemp, icon: weather.currentIcon,
                                    precipChance: 0, precipMm: nil, isStandIn: true))
            t = s
        }
        out.insert(contentsOf: lead.reversed(), at: 0)
        return out
    }

    /// The temperature range the curve's band represents: the data, widened to 14° so a
    /// flat day looks flat.
    public static func tempScale(_ slots: [HorizonSlot]) -> (lo: Double, hi: Double) {
        let temps = slots.map(\.temp)
        guard var lo = temps.min(), var hi = temps.max() else { return (0, 1) }
        if hi - lo < 14 {
            let mid = (hi + lo) / 2
            lo = mid - 7
            hi = mid + 7
        }
        return (lo, hi)
    }

    /// Each day's high and low inside the window, labelled only where it is a real turning
    /// point: the window cuts days at both ends, and the warmest slot of a cut evening is
    /// where the curve starts falling, not the day's high. Stand-ins are never labelled.
    public static func extremes(_ slots: [HorizonSlot], axis: TimeAxis) -> [Extreme] {
        var byDay: [CivilDate: [Int]] = [:]
        for (i, s) in slots.enumerated() where s.start >= axis.start && s.start <= axis.end && !s.isStandIn {
            byDay[CivilDate(s.start, in: axis.zone), default: []].append(i)
        }
        var out: [Extreme] = []
        for day in byDay.keys.sorted() {
            let idx = byDay[day]!
            for kind in [Extreme.Kind.high, .low] {
                let i = kind == .high
                    ? idx.max { slots[$0].temp < slots[$1].temp }!
                    : idx.min { slots[$0].temp < slots[$1].temp }!
                guard i > 0, i < slots.count - 1 else { continue }
                let (t, before, after) = (slots[i].temp, slots[i - 1].temp, slots[i + 1].temp)
                let turning = kind == .high ? t >= before && t >= after : t <= before && t <= after
                if turning { out.append(Extreme(kind: kind, time: slots[i].start, temp: t)) }
            }
        }
        return out
    }

    /// True when the slot holding *t* is overcast or wet.
    public static func hidden(at t: Date, in slots: [HorizonSlot]) -> Bool {
        slots.first { $0.start <= t && t < $0.end }?.sky.hidesBodies ?? false
    }

    /// How dense a rain bar is: the expected amount, or the chance without one.
    public static func rainCover(mm: Double?, chance: Double) -> Double {
        guard let mm else { return 0.25 + 0.35 * chance }
        return min(1, 0.3 + mm / 4)
    }

    /// Three facts worth reading without the chart: the warmest and coldest slot and the
    /// first stretch of rain, from forecast slots only (the stand-ins repeat the reading now).
    public static func outlook(_ slots: [HorizonSlot], axis: TimeAxis) -> [(label: String, value: String)] {
        let inside = slots.filter { $0.start >= axis.start && $0.start < axis.end && !$0.isStandIn }
        guard let warm = inside.max(by: { $0.temp < $1.temp }),
              let cold = inside.min(by: { $0.temp < $1.temp }) else { return [] }
        let zone = axis.zone
        func when(_ t: Date) -> String {
            "\(t.formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated))) \(CompactTime.string(t, in: zone))"
        }
        var rows = [
            ("WARMEST", "\(when(warm.start)) · \(Int(warm.temp.rounded()))°"),
            ("COLDEST", "\(when(cold.start)) · \(Int(cold.temp.rounded()))°"),
        ]
        let wet = inside.filter { $0.precipChance >= 0.3 }
        if let first = wet.first {
            var run = [first]
            for s in wet.dropFirst() {
                guard s.start == run[run.count - 1].end else { break }
                run.append(s)
            }
            let end = run[run.count - 1].end
            let peak = run.map(\.precipChance).max() ?? 0
            let until = Calendar.gregorian(zone).component(.hour, from: end) == 0
                ? "midnight" : CompactTime.string(end, in: zone)
            rows.append(("RAIN", "\(when(first.start))–\(until) · \(Int((peak * 100).rounded()))%"))
        } else {
            rows.append(("RAIN", "none in sight"))
        }
        return rows
    }
}

// MARK: - The moon

extension Horizon {
    /// When the moon crosses the meridian on the night after *day*: noon at new moon,
    /// midnight at full, about 50 minutes later each day between. Close enough to place a
    /// disc on the axis. Nil when the Pi's `moon` block does not cover *day*.
    public static func moonTransit(on day: CivilDate, moon: Moon, zone: TimeZone) -> (time: Date, fraction: Double)? {
        guard let entry = moon.days.first(where: { $0.date == day }) else { return nil }
        let hours = 12 + 24 * entry.ageDays / 29.530588
        return (day.start(in: zone).addingTimeInterval(hours * 3600), entry.fraction)
    }
}

// MARK: - The calendar

/// An all-day event or a birthday as a chip over the days it covers.
public struct AllDayChip: Sendable, Equatable {
    public var start: Date
    public var end: Date
    public var label: String
    /// What a chip too narrow for *label* shows: "Mom" for "Mom's birthday".
    public var short: String
    public var isBirthday: Bool
}

extension Horizon {
    /// Timed events overlapping the window, by start.
    public static func timedEvents(_ snapshot: Snapshot, axis: TimeAxis) -> [CalendarEvent] {
        (snapshot.sources.events?.data ?? [])
            .filter { !$0.isAllDay && $0.start < axis.end && $0.end > axis.start }
            .sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    }

    /// All-day spans and birthdays in the window.
    public static func allDayChips(_ snapshot: Snapshot, axis: TimeAxis) -> [AllDayChip] {
        let zone = axis.zone
        var chips: [AllDayChip] = []
        for e in snapshot.sources.events?.data ?? [] where e.isAllDay {
            let start = CivilDate(e.start, in: zone).start(in: zone)
            var end = CivilDate(e.end, in: zone).start(in: zone)
            if end <= start { end = CivilDate(e.start, in: zone).adding(days: 1).start(in: zone) }
            if start < axis.end && end > axis.start {
                chips.append(AllDayChip(start: start, end: end, label: e.summary, short: e.summary, isBirthday: false))
            }
        }
        let first = CivilDate(axis.start, in: zone)
        for b in snapshot.sources.birthdays?.data ?? [] where b.date >= first {
            let start = b.date.start(in: zone)
            guard start < axis.end else { continue }
            let label = b.age.map { "\(b.name) turns \($0)" } ?? "\(b.name)'s birthday"
            chips.append(AllDayChip(start: start, end: b.date.adding(days: 1).start(in: zone),
                                    label: label, short: b.name, isBirthday: true))
        }
        return chips.sorted { a, b in
            if a.start != b.start { return a.start < b.start }
            if a.isBirthday != b.isBirthday { return !a.isBirthday }
            return a.label < b.label
        }
    }

    /// Rows of chips, multi-day spans above the single days they cross: spans are seated
    /// first, each in the first row free across its extent; a single day then takes the first
    /// free row below every span it overlaps, so a week-long trip never sits under Tuesday's
    /// dentist, while a day no span crosses starts at the top.
    public static func stackChips<T>(_ items: [(x0: Double, x1: Double, multiDay: Bool, chip: T)]) -> [[T]] {
        var rows: [[(Double, Double)]] = []
        var placed: [[T]] = []
        var spanRows: [(Double, Double, Int)] = []

        func seat(_ x0: Double, _ x1: Double, _ chip: T, floor: Int) -> Int {
            var ri = floor
            while ri < rows.count && !rows[ri].allSatisfy({ $0.1 <= x0 || $0.0 >= x1 }) { ri += 1 }
            while rows.count <= ri {
                rows.append([])
                placed.append([])
            }
            rows[ri].append((x0, x1))
            placed[ri].append(chip)
            return ri
        }

        let spans = items.filter(\.multiDay).sorted { ($0.x0, -($0.x1 - $0.x0)) < ($1.x0, -($1.x1 - $1.x0)) }
        for s in spans { spanRows.append((s.x0, s.x1, seat(s.x0, s.x1, s.chip, floor: 0))) }
        for s in items.filter({ !$0.multiDay }).sorted(by: { $0.x0 < $1.x0 }) {
            let over = spanRows.filter { $0.0 < s.x1 && $0.1 > s.x0 }.map(\.2)
            _ = seat(s.x0, s.x1, s.chip, floor: over.max().map { $0 + 1 } ?? 0)
        }
        return placed
    }

    /// The day whose column lists *event*: its start, or the window's first day if earlier.
    public static func columnDay(_ event: CalendarEvent, axis: TimeAxis) -> CivilDate {
        CivilDate(max(event.start, axis.start), in: axis.zone)
    }

    /// A list row's time: the start, or "–end" for one begun before the window.
    public static func rowTime(_ event: CalendarEvent, axis: TimeAxis) -> String {
        event.start < axis.start
            ? "–\(CompactTime.string(event.end, in: axis.zone))"
            : CompactTime.string(event.start, in: axis.zone)
    }

    /// (rows drawn, the count for "+N more") for a day with room for *available* rows. The
    /// last row carries the count rather than an event, so a day never ends on a row that
    /// pretends to be its last.
    public static func listRows(events: Int, hidden: Int, available: Int) -> (shown: Int, more: Int) {
        if events <= available && hidden == 0 { return (events, 0) }
        let shown = max(0, min(events, available - 1))
        return (shown, events - shown + hidden)
    }

    /// A day's header name: TODAY (TONIGHT once the window starts at 18:00), TOMORROW, then
    /// the weekday.
    public static func dayName(_ day: CivilDate, now: Date, axis: TimeAxis) -> String {
        let zone = axis.zone
        let today = CivilDate(now, in: zone)
        if day == today {
            return Calendar.gregorian(zone).component(.hour, from: axis.start) >= 18 ? "TONIGHT" : "TODAY"
        }
        if day == today.adding(days: 1) { return "TOMORROW" }
        return day.start(in: zone).formatted(Date.FormatStyle(timeZone: zone).weekday(.wide)).uppercased()
    }
}
