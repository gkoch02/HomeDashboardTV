import DashboardCore
import SwiftUI

private enum Palette {
    static let night = Color(red: 0.05, green: 0.06, blue: 0.09)
    static let dusk = Color(red: 0.09, green: 0.12, blue: 0.20)
    static let day = Color(red: 0.13, green: 0.19, blue: 0.30)
    static let ink = Color(white: 0.96)
    static let muted = Color(white: 0.70)
    static let faint = Color(white: 0.45)
    static let card = Color.white.opacity(0.06)
    static let today = Color(red: 0.98, green: 0.78, blue: 0.42)
    static let alert = Color(red: 1.0, green: 0.78, blue: 0.30)
}

/// The dashboard at TV distance: the clock, weather and quote down the left, today's agenda
/// large on the right with the next six days beneath it.
///
/// Every time and day is the Pi's zone (`Snapshot.timeZone`), so the TV agrees with the panel.
/// It fills the screen to a 56 x 44 pt margin, past tvOS's overscan safe area.
struct DashboardView: Theme {
    let snapshot: Snapshot
    let now: Date

    static let fullBleed = true

    private var zone: TimeZone { snapshot.timeZone }

    private static let columnSpacing: CGFloat = 34
    /// Two rows of day cards, each tall enough for a header and four one-line events.
    private static let minimumGridHeight: CGFloat = 2 * 210 + 24

    var body: some View {
        let days = Agenda.days(from: snapshot, now: now, count: 7)
        HStack(alignment: .top, spacing: 52) {
            LeftColumn(snapshot: snapshot, now: now)
                .frame(width: 540)
            AgendaColumn(spacing: Self.columnSpacing, minimumGridHeight: Self.minimumGridHeight) {
                TodayPanel(day: days[0], zone: zone, now: now)
                UpcomingGrid(days: Array(days.dropFirst()), zone: zone)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // One margin, ours, instead of tvOS's overscan safe area plus ours (176 pt a side in
        // all): a TV that shows the whole picture wasted it, and the day cards need it. The
        // margin still holds the burn-in drift (10 pt) clear of the edge.
        .padding(.horizontal, 56)
        .padding(.vertical, 44)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Day sky between sunrise and sunset, night sky otherwise, and dusk for the half hour
    /// either side. Without sun times (no weather) the night sky.
    var backdrop: some View {
        let top: Color
        if let rise = snapshot.sources.weather?.data?.sunrise,
           let set = snapshot.sources.weather?.data?.sunset {
            let today = CivilDate(now, in: zone)
            let rise = rise.addingTimeInterval(dayShift(rise, to: today))
            let set = set.addingTimeInterval(dayShift(set, to: today))
            if now > rise.addingTimeInterval(1800) && now < set.addingTimeInterval(-1800) {
                top = Palette.day
            } else if now > rise.addingTimeInterval(-1800) && now < set.addingTimeInterval(1800) {
                top = Palette.dusk
            } else {
                top = Palette.night
            }
        } else {
            top = Palette.night
        }
        return LinearGradient(colors: [top, Palette.night], startPoint: .top, endPoint: .bottom)
    }

    /// The Pi's sun times are for the day it fetched; carry them to *today* so a cache from
    /// yesterday evening does not paint today's morning as night.
    private func dayShift(_ date: Date, to today: CivilDate) -> TimeInterval {
        let from = CivilDate(date, in: zone).start(in: zone)
        return today.start(in: zone).timeIntervalSince(from)
    }
}

/// Today above the day cards. Today is measured against everything the cards can spare, so it
/// picks the richest of its layouts that fits, and is as tall as that layout; the cards take
/// the rest, never less than `minimumGridHeight`.
private struct AgendaColumn: Layout {
    let spacing: CGFloat
    let minimumGridHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let budget = max(bounds.height - spacing - minimumGridHeight, 0)
        let today = subviews[0].sizeThatFits(ProposedViewSize(width: bounds.width, height: budget))
        let todayHeight = min(today.height, budget)
        subviews[0].place(
            at: bounds.origin,
            proposal: ProposedViewSize(width: bounds.width, height: todayHeight)
        )
        let gridTop = bounds.minY + todayHeight + spacing
        subviews[1].place(
            at: CGPoint(x: bounds.minX, y: gridTop),
            proposal: ProposedViewSize(width: bounds.width, height: bounds.maxY - gridTop)
        )
    }
}

// MARK: - Left column

private struct LeftColumn: View {
    let snapshot: Snapshot
    let now: Date
    @Environment(\.timeZone) private var zone

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(now.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)))
                .font(.system(size: 156, weight: .thin, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(now.formatted(Date.FormatStyle(timeZone: zone).weekday(.wide).month(.wide).day()))
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Palette.muted)
                .padding(.bottom, 48)

            if let weather = snapshot.sources.weather?.data {
                CurrentWeather(
                    weather: weather,
                    metric: snapshot.isMetric,
                    airQuality: snapshot.sources.airQuality?.data
                )
                    .padding(.bottom, 36)
                ForecastRow(days: Array(weather.forecast.prefix(5)), zone: zone)
            } else {
                Text("No weather yet")
                    .font(.system(size: 28))
                    .foregroundStyle(Palette.faint)
            }

            Spacer(minLength: 32)

            if let quote = snapshot.quote {
                VStack(alignment: .leading, spacing: 12) {
                    Text("“\(quote.text)”")
                        .font(.system(size: 28, design: .serif).italic())
                        .foregroundStyle(Palette.muted)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("— \(quote.author)")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Palette.faint)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct CurrentWeather: View {
    let weather: Weather
    let metric: Bool
    let airQuality: AirQuality?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 28) {
                Image(systemName: WeatherSymbol.name(for: weather.currentIcon))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 92))
                    .frame(width: 120)
                VStack(alignment: .leading, spacing: 4) {
                    Text(degrees(weather.currentTemp))
                        .font(.system(size: 96, weight: .light, design: .rounded))
                        .foregroundStyle(Palette.ink)
                    Text(weather.currentDescription.capitalized)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Ahead of the badge and the spacer: a long description ("Thunderstorm With
                // Heavy Rain") wraps beside the badge rather than pushing it off.
                .layoutPriority(1)
                Spacer(minLength: 0)
                if let airQuality {
                    AQIBadge(airQuality: airQuality)
                }
            }
            HStack(spacing: 28) {
                stat("arrow.up", degrees(weather.high))
                stat("arrow.down", degrees(weather.low))
                if let feels = weather.feelsLike { stat("thermometer.medium", "feels \(degrees(feels))") }
                stat("humidity", "\(weather.humidity)%")
            }
            ForEach(weather.alerts, id: \.self) { alert in
                Label(alert.event, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Palette.alert)
            }
        }
    }

    private func degrees(_ value: Double) -> String { "\(Int(value.rounded()))°" }

    private func stat(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 24, weight: .medium))
            .foregroundStyle(Palette.muted)
            .labelStyle(.titleAndIcon)
    }
}

private struct ForecastRow: View {
    let days: [DayForecast]
    let zone: TimeZone

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                VStack(spacing: 10) {
                    Text(day.date.start(in: zone).formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated)))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                    Image(systemName: WeatherSymbol.name(for: day.icon))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 36))
                        .frame(height: 44)
                    Text("\(Int(day.high.rounded()))°")
                        .font(.system(size: 26, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.ink)
                    Text("\(Int(day.low.rounded()))°")
                        .font(.system(size: 22, design: .rounded))
                        .foregroundStyle(Palette.faint)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 22)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// Air quality beside the temperature, as prominent as it: the number in its EPA band's
/// colour on a tile tinted the same, so a bad-air day reads from across the room.
private struct AQIBadge: View {
    let airQuality: AirQuality

    var body: some View {
        VStack(spacing: 2) {
            Text("AQI")
                .font(.system(size: 18, weight: .bold))
                .tracking(2)
                .foregroundStyle(Palette.muted)
            Text("\(airQuality.aqi)")
                .font(.system(size: 64, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(airQuality.shortLabel)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(color)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
        }
        .padding(.vertical, 14)
        .frame(width: 164)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(color.opacity(0.45), lineWidth: 2)
        )
    }

    /// The EPA's band colours, lifted a little so they read on the dark ground.
    private var color: Color {
        switch airQuality.band {
        case .good: return Color(red: 0.36, green: 0.82, blue: 0.42)
        case .moderate: return Color(red: 0.98, green: 0.86, blue: 0.30)
        case .sensitive: return Color(red: 1.0, green: 0.60, blue: 0.22)
        case .unhealthy: return Color(red: 1.0, green: 0.35, blue: 0.33)
        case .veryUnhealthy: return Color(red: 0.72, green: 0.45, blue: 0.95)
        case .hazardous: return Color(red: 0.80, green: 0.30, blue: 0.40)
        }
    }
}

// MARK: - Agenda

/// Today's events at reading size. Its height is capped by `DashboardView` so the day cards
/// keep their room; it shows the richest layout that fits: every event with locations, then
/// without, then fewer events with a count of the rest.
private struct TodayPanel: View {
    let day: AgendaDay
    let zone: TimeZone
    let now: Date

    private var upcoming: [CalendarEvent] { day.events.filter { $0.isAllDay || $0.end > now } }

    var body: some View {
        let layouts = Self.layouts(events: upcoming.count)
        ViewThatFits(in: .vertical) {
            ForEach(layouts.indices, id: \.self) { i in
                content(rows: layouts[i].rows, locations: layouts[i].locations)
            }
        }
        .padding(36)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    /// All *events* rows, then fewer, never one fewer: "+1 more" takes the line the event
    /// would have.
    private static func layouts(events: Int) -> [(rows: Int, locations: Bool)] {
        [(events, true), (events, false)] + (0..<max(events - 1, 0)).reversed().map { ($0, false) }
    }

    private func content(rows: Int, locations: Bool) -> some View {
        let upcoming = upcoming
        let finished = day.events.count - upcoming.count
        let hidden = upcoming.count - min(rows, upcoming.count)
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Palette.today)
                Spacer()
                if finished > 0 {
                    Text("\(finished) done")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Palette.faint)
                }
            }
            ForEach(day.birthdays, id: \.self) { birthday in
                BirthdayLine(birthday: birthday, size: 30)
            }
            if upcoming.isEmpty && day.birthdays.isEmpty {
                Text(day.events.isEmpty ? "Nothing on the calendar" : "That's everything for today")
                    .font(.system(size: 30))
                    .foregroundStyle(Palette.faint)
                    .padding(.vertical, 8)
            }
            ForEach(upcoming.prefix(rows), id: \.self) { event in
                TodayRow(event: event, zone: zone, now: now, showsLocation: locations)
            }
            if hidden > 0 {
                Text(rows == 0 ? "\(hidden) events" : "+\(hidden) more")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Palette.faint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TodayRow: View {
    let event: CalendarEvent
    let zone: TimeZone
    let now: Date
    var showsLocation = true

    var body: some View {
        let happening = !event.isAllDay && event.start <= now && event.end > now
        HStack(alignment: .firstTextBaseline, spacing: 28) {
            Text(event.isAllDay ? "All day" : event.start.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)))
                .font(.system(size: 30, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(happening ? Palette.today : Palette.muted)
                .frame(width: 170, alignment: .trailing)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.summary)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if showsLocation, let location = event.shortLocation {
                    Text(location)
                        .font(.system(size: 24))
                        .foregroundStyle(Palette.faint)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if happening {
                Text("Now")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .background(Palette.today, in: Capsule())
            }
        }
    }
}

/// Two rows of three cards sharing the height left under Today, so a busy day cannot push
/// its row (or the screen) taller.
private struct UpcomingGrid: View {
    let days: [AgendaDay]
    let zone: TimeZone

    private static let spacing: CGFloat = 24

    var body: some View {
        GeometryReader { geometry in
            let rows = stride(from: 0, to: days.count, by: 3).map { Array(days[$0..<min($0 + 3, days.count)]) }
            let height = (geometry.size.height - Self.spacing * CGFloat(max(rows.count - 1, 0)))
                / CGFloat(max(rows.count, 1))
            VStack(spacing: Self.spacing) {
                ForEach(rows, id: \.first?.id) { row in
                    HStack(spacing: Self.spacing) {
                        ForEach(row) { day in
                            DayCard(day: day, zone: zone)
                                .frame(height: height)
                        }
                    }
                }
            }
        }
    }
}

/// One upcoming day. The card's height is fixed by the grid; it shows the richest layout that
/// fits: every event, names and titles wrapping to two lines, then names only (a birthday is
/// rarer than an event), then neither, then fewer events with a count of the rest.
private struct DayCard: View {
    let day: AgendaDay
    let zone: TimeZone

    /// All *events* rows, then fewer, never one fewer: "+1 more" takes the line the event
    /// would have.
    private static func layouts(events: Int) -> [(rows: Int, titleLines: Int, nameLines: Int)] {
        [(events, 2, 2), (events, 1, 2), (events, 1, 1)]
            + (0..<max(events - 1, 0)).reversed().map { ($0, 1, 1) }
    }

    var body: some View {
        let layouts = Self.layouts(events: day.events.count)
        ViewThatFits(in: .vertical) {
            ForEach(layouts.indices, id: \.self) { i in
                let layout = layouts[i]
                content(rows: layout.rows, titleLines: layout.titleLines, nameLines: layout.nameLines)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func content(rows: Int, titleLines: Int, nameLines: Int) -> some View {
        let date = day.day.start(in: zone)
        let shown = Array(day.events.prefix(rows))
        let labels = shown.map { $0.isAllDay ? "•" : compactTime($0.start) }
        // Every row reserves the width of this card's longest time, so the titles line up
        // and get the rest of the card.
        let widest = labels.max { $0.count < $1.count } ?? ""
        let hidden = day.events.count - shown.count
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(date.formatted(Date.FormatStyle(timeZone: zone).weekday(.wide)))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Text(date.formatted(Date.FormatStyle(timeZone: zone).month(.abbreviated).day()))
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Palette.faint)
            }
            .padding(.bottom, 3)
            ForEach(day.birthdays, id: \.self) { birthday in
                BirthdayLine(birthday: birthday, size: 22, compact: true, lines: nameLines)
            }
            if day.events.isEmpty && day.birthdays.isEmpty {
                Text("Free")
                    .font(.system(size: 22))
                    .foregroundStyle(Palette.faint)
            }
            ForEach(Array(zip(shown, labels)), id: \.0) { event, label in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    ZStack(alignment: .trailing) {
                        Text(widest).hidden()
                        Text(label).foregroundStyle(Palette.faint)
                    }
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    Text(event.summary)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(titleLines)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if hidden > 0 {
                HStack(spacing: 12) {
                    Text(widest).hidden()
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .monospacedDigit()
                    Text(shown.isEmpty ? "\(hidden) events" : "+\(hidden) more")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Palette.faint)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "9a", "11:30a", "2p": the cards are a third of the agenda wide, and a full "11:30 AM"
    /// column leaves a title a dozen characters.
    private func compactTime(_ date: Date) -> String { CompactTime.string(date, in: zone) }
}

private struct BirthdayLine: View {
    let birthday: Birthday
    let size: CGFloat
    /// The day cards are a third of the agenda wide: the name with the age beside it, wrapping
    /// to a second line rather than cutting a long name short.
    var compact = false
    var lines = 2

    var body: some View {
        Label {
            if compact {
                (Text(birthday.name)
                    + Text(birthday.age.map { "  \($0)" } ?? "")
                    .foregroundColor(Palette.today))
                    .lineLimit(lines)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(birthday.age.map { "\(birthday.name) turns \($0)" } ?? "\(birthday.name)'s birthday")
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: "gift.fill").foregroundStyle(Palette.today)
        }
        .font(.system(size: size, weight: .semibold))
        .foregroundStyle(Palette.ink)
    }
}
