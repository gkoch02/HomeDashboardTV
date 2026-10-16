import DashboardCore
import SwiftUI

/// The Agenda layout: the spiritual successor to the Pi's `halftone_agenda`, as a dark plate
/// for a big screen:
/// the weather and its reading on the left, the day's agenda on the right.
///
/// Cream type on a warm charcoal ground, with the Pi's two Inky spot inks: ochre for the sun,
/// the moon's ring and the lightning, red for the event in progress and the next one up. The
/// weather window is `WeatherArt`, painted at full resolution. Elapsed events fade back (the
/// Pi perforates them, which on a TV reads as a checkerboard). Type is the Pi's own: Righteous
/// for the weather and the agenda's chrome, DM Sans for the events.
///
/// As the layout appears the weather window prints down from the top, the rule runs down
/// beside it, and the reading and the agenda's lines rise in after.
struct AgendaPlateView: Theme {
    let snapshot: Snapshot
    let now: Date

    @State private var build = AgendaBuild.start

    static let fullBleed = true

    private var zone: TimeZone { snapshot.timeZone }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let artWidth = (size.width * 0.46).rounded()
            let artHeight = (size.height * 0.6).rounded()
            ZStack(alignment: .topLeading) {
                // The window bleeds past the screen edge so the burn-in drift never shows one.
                Group {
                    if let weather = snapshot.sources.weather?.data {
                        WeatherArt(
                            icon: weather.currentIcon,
                            moonFraction: snapshot.moon?.today?.fraction,
                            size: CGSize(width: artWidth + 24, height: artHeight + 24),
                            light: Print.ink,
                            accent: Print.ochre
                        )
                        .equatable()
                    } else {
                        Print.ink.opacity(0.05)
                    }
                }
                .frame(width: artWidth + 24, height: artHeight + 24)
                .clipped()  // before the offset, so the bleed past the top and left survives
                .wipe(build.art, from: .top, softness: 0.12)
                .offset(x: -24, y: -24)
                .overlay(alignment: .topLeading) { alertChip.padding(.leading, 56).padding(.top, 44) }

                WeatherBand(snapshot: snapshot, now: now)
                    .frame(width: artWidth - 56 - 40, height: size.height - artHeight - 28 - 40, alignment: .topLeading)
                    .opacity(build.band)
                    .offset(x: 56, y: artHeight + 28 + (1 - build.band) * 24)

                ScreenRule()
                    .frame(width: 10, height: size.height + 48)
                    .wipe(build.rule, from: .top, softness: 0.1)
                    .offset(x: artWidth, y: -24)

                AgendaPane(snapshot: snapshot, now: now, rise: build.agenda)
                    .frame(width: size.width - artWidth - 10 - 64 - 56, height: size.height - 44 - 40)
                    .offset(x: artWidth + 10 + 64, y: 44)
            }
        }
        .onBuildIn(reset: { settled in build = settled ? .settled : .start }) {
            withAnimation(.easeInOut(duration: 1.5).delay(0.05)) { build.art = 1 }
            withAnimation(.easeInOut(duration: 1.1).delay(0.2)) { build.rule = 1 }
            withAnimation(.linear(duration: 1.5).delay(0.45)) { build.agenda = 1 }
            withAnimation(.easeOut(duration: 0.8).delay(1.2)) { build.band = 1 }
        }
    }

    var backdrop: some View { Print.paper }

    func notice(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.custom(Print.display, size: 20))
            .foregroundStyle(Print.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background { Print.red }  // a bare colour would run up into the safe area
    }

    @ViewBuilder private var alertChip: some View {
        if let alert = snapshot.sources.weather?.data?.alerts.first {
            Text(alert.event.uppercased())
                .font(.custom(Print.display, size: 26))
                .foregroundStyle(Print.ink)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Print.red)
        }
    }
}

/// How far the build-in has got, each part 0 to 1.
private struct AgendaBuild {
    var art: Double
    var rule: Double
    var band: Double
    var agenda: Double

    static let start = AgendaBuild(art: 0, rule: 0, band: 0, agenda: 0)
    static let settled = AgendaBuild(art: 1, rule: 1, band: 1, agenda: 1)
}

/// The plate's inks and faces. `paper` is the ground and `ink` the type, so the inverted
/// treatments (the running event, the TOMORROW chip) read the same as on the Pi's light plate.
private enum Print {
    static let paper = Color(red: 0.080, green: 0.076, blue: 0.088)
    static let ink = Color(red: 0.925, green: 0.895, blue: 0.835)
    static let red = Color(red: 0.88, green: 0.33, blue: 0.25)
    static let ochre = Color(red: 0.92, green: 0.69, blue: 0.22)
    static let faint = Color(red: 0.925, green: 0.895, blue: 0.835).opacity(0.55)

    static let display = "Righteous-Regular"
    static let text = "DMSans-9ptRegular"
}

/// The full-height rule between the panes: a narrow strip of fine screen.
private struct ScreenRule: View {
    var body: some View {
        Canvas { context, size in
            let p: CGFloat = 4
            var path = Path()
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? 0 : p / 2
                while x < size.width {
                    path.addEllipse(in: CGRect(x: x, y: y, width: 2.6, height: 2.6))
                    x += p
                }
                y += p / 2
                row += 1
            }
            context.fill(path, with: .color(Print.ink.opacity(0.35)))
        }
    }
}

// MARK: - The weather band

private struct WeatherBand: View {
    let snapshot: Snapshot
    let now: Date
    @Environment(\.timeZone) private var zone

    var body: some View {
        if let weather = snapshot.sources.weather?.data {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 34) {
                    Text("\(Int(weather.currentTemp.rounded()))°")
                        .font(.custom(Print.display, size: 168))
                        .foregroundStyle(Print.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .layoutPriority(1)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(weather.currentDescription.uppercased())
                            .font(.custom(Print.display, size: 38))
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                        Text("H \(Int(weather.high.rounded()))°  ·  L \(Int(weather.low.rounded()))°")
                            .font(.custom(Print.text, size: 36).weight(.semibold))
                    }
                    .foregroundStyle(Print.ink)
                }
                Rectangle().fill(Print.ink).frame(height: 2)
                HStack {
                    if let rise = weather.sunrise { sun("sunrise", rise) }
                    Spacer()
                    if let set = weather.sunset { sun("sunset", set) }
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(dateline)
                        .font(.custom(Print.display, size: 32))
                    Spacer()
                    Text(footnote(weather))
                        .font(.custom(Print.text, size: 24).weight(.semibold))
                        .tracking(1.5)
                }
                .foregroundStyle(Print.ink)
            }
        } else {
            Text("NO WEATHER YET")
                .font(.custom(Print.display, size: 40))
                .foregroundStyle(Print.faint)
        }
    }

    private func sun(_ symbol: String, _ date: Date) -> some View {
        Label {
            Text(date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)))
                .font(.custom(Print.text, size: 32).weight(.semibold))
        } icon: {
            Image(systemName: symbol).font(.system(size: 30, weight: .semibold))
        }
        .foregroundStyle(Print.ink)
    }

    /// "WED · OCT 14 · 2026".
    private var dateline: String {
        let style = Date.FormatStyle(timeZone: zone)
        let weekday = now.formatted(style.weekday(.abbreviated))
        let monthDay = now.formatted(style.month(.abbreviated).day())
        let year = now.formatted(style.year())
        return "\(weekday) · \(monthDay) · \(year)".uppercased()
    }

    private func footnote(_ weather: Weather) -> String {
        var parts: [String] = []
        if let feels = weather.feelsLike { parts.append("FEELS \(Int(feels.rounded()))°") }
        if let aqi = snapshot.sources.airQuality?.data { parts.append("AQI \(aqi.aqi)") }
        return parts.joined(separator: "  ·  ")
    }
}

// MARK: - The agenda

private struct AgendaPane: View {
    let snapshot: Snapshot
    let now: Date
    /// The build-in's progress: the header, then each line in turn.
    let rise: Double
    @Environment(\.timeZone) private var zone

    var body: some View {
        let (day, tomorrow) = Agenda.rolloverDay(from: snapshot, now: now)
        let rows = day.birthdays.map(Row.birthday) + day.events.map(Row.event)
        let next = day.events.first { !$0.isAllDay && $0.start > now }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 22) {
                if tomorrow {
                    Text("TOMORROW")
                        .font(.custom(Print.display, size: 48))
                        .foregroundStyle(Print.paper)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 2)
                        .background(Print.ink)
                } else {
                    Text("TODAY")
                        .font(.custom(Print.display, size: 56))
                        .foregroundStyle(Print.ink)
                }
                Text(count(day.events.count))
                    .font(.custom(Print.text, size: 24).weight(.bold))
                    .tracking(2)
                    .foregroundStyle(Print.faint)
                Spacer()
                clock
            }
            .rise(rise, index: 0, of: rows.count + 2)
            Rectangle().fill(Print.ink).frame(height: 4).padding(.top, 10).padding(.bottom, 26)
                .rise(rise, index: 0, of: rows.count + 2)

            ViewThatFits(in: .vertical) {
                ForEach((0...rows.count).reversed(), id: \.self) { shown in
                    list(Array(rows.prefix(shown)), hidden: rows.count - shown, next: next)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                    .opacity(rise)
                if let fetched = snapshot.sources.events?.fetchedAt {
                    Text("updated \(fetched.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)).lowercased())")
                        .font(.custom(Print.text, size: 22).weight(.medium))
                        .foregroundStyle(Print.faint)
                        .opacity(rise)
                }
            }
        }
    }

    /// The time now, set like TODAY across from it; the minute redraws keep it current. A
    /// 12-hour locale gets a small AM or PM in the faint ink.
    private var clock: Text {
        let parts = ClockTime.parts(now, in: zone)
        var text = Text(parts.time)
            .font(.custom(Print.display, size: 56))
            .foregroundColor(Print.ink)
        if let period = parts.period {
            text = text + Text(" " + period)
                .font(.custom(Print.text, size: 24).weight(.bold))
                .tracking(2)
                .foregroundColor(Print.faint)
        }
        return text
    }

    private func count(_ n: Int) -> String {
        n == 0 ? "NO EVENTS" : n == 1 ? "1 EVENT" : "\(n) EVENTS"
    }

    @ViewBuilder
    private func list(_ rows: [Row], hidden: Int, next: CalendarEvent?) -> some View {
        let count = rows.count + 2
        VStack(alignment: .leading, spacing: 22) {
            if rows.isEmpty && hidden == 0 {
                Text("A clear day.")
                    .font(.custom(Print.text, size: 40).weight(.medium))
                    .foregroundStyle(Print.faint)
                    .rise(rise, index: 1, of: count)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                Group {
                    switch row {
                    case .birthday(let b):
                        BirthdayRow(birthday: b)
                    case .event(let e):
                        EventRow(event: e, state: state(of: e, next: next), zone: zone)
                    }
                }
                .rise(rise, index: 1 + index, of: count)
            }
            if hidden > 0 {
                Text("+\(hidden) more")
                    .font(.custom(Print.text, size: 28).weight(.bold))
                    .foregroundStyle(Print.ink)
                    .padding(.leading, EventRow.timeWidth + 30)
                    .rise(rise, index: count - 1, of: count)
            }
        }
    }

    private func state(of event: CalendarEvent, next: CalendarEvent?) -> EventRow.State {
        if event.isAllDay { return .upcoming }
        if event.end <= now { return .elapsed }
        if event.start <= now { return .running }
        return event == next ? .next : .upcoming
    }

    enum Row: Identifiable {
        case birthday(Birthday)
        case event(CalendarEvent)

        var id: String {
            switch self {
            case .birthday(let b): return "b-\(b.name)"
            case .event(let e): return "e-\(e.summary)-\(e.start.timeIntervalSince1970)"
            }
        }
    }
}

private struct EventRow: View {
    enum State { case elapsed, running, next, upcoming }

    let event: CalendarEvent
    let state: State
    let zone: TimeZone

    static let timeWidth: CGFloat = 150

    var body: some View {
        let inverted = state == .running
        let ink = Print.ink
        HStack(alignment: .top, spacing: 18) {
            // The start reads at a glance; the end sits under it, smaller and quieter.
            VStack(alignment: .trailing, spacing: 2) {
                if event.isAllDay {
                    Text("ALL DAY").font(.custom(Print.text, size: 24).weight(.bold)).tracking(1.5)
                        .foregroundStyle(ink)
                } else {
                    Text(CompactTime.string(event.start, in: zone))
                        .font(.custom(Print.text, size: 30).weight(.semibold))
                        .foregroundStyle(ink)
                    Text("to \(CompactTime.string(event.end, in: zone))")
                        .font(.custom(Print.text, size: 22).weight(.medium))
                        .foregroundStyle(inverted ? Print.ink.opacity(0.75) : Print.faint)
                }
            }
            .frame(width: Self.timeWidth, alignment: .trailing)

            Rectangle()
                .fill(state == .running || state == .next ? Print.red : .clear)
                .frame(width: 7)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.summary)
                    .font(.custom(Print.text, size: 44).weight(.bold))
                    .foregroundStyle(ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let location = event.shortLocation {
                    Text(location)
                        .font(.custom(Print.text, size: 28).weight(.medium))
                        .foregroundStyle(inverted ? Print.ink.opacity(0.75) : Print.faint)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        // Finished events step back rather than vanish.
        .opacity(state == .elapsed ? 0.4 : 1)
        .padding(.vertical, inverted ? 14 : 0)
        .padding(.trailing, inverted ? 18 : 0)
        // On the dark plate "inverted" is a quiet lift, not a cream bar: the brightest block on
        // a big screen should not be a meeting.
        .background(inverted ? Print.ink.opacity(0.1) : .clear)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct BirthdayRow: View {
    let birthday: Birthday

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Image(systemName: "gift.fill")
                .font(.system(size: 30))
                .foregroundStyle(Print.red)
                .frame(width: EventRow.timeWidth, alignment: .trailing)
            Rectangle().fill(.clear).frame(width: 7)
            Text(birthday.age.map { "\(birthday.name) turns \($0)" } ?? "\(birthday.name)'s birthday")
                .font(.custom(Print.text, size: 40).weight(.bold))
                .foregroundStyle(Print.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}
