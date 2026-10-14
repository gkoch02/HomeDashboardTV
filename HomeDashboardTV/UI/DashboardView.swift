import DashboardCore
import SwiftUI

enum Palette {
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
/// The content drifts a few points every ten minutes so an OLED set never holds one image.
struct DashboardView: View {
    let snapshot: Snapshot
    let now: Date
    let notice: String?

    private var zone: TimeZone { snapshot.timeZone }

    var body: some View {
        let days = Agenda.days(from: snapshot, now: now, count: 7)
        HStack(alignment: .top, spacing: 70) {
            LeftColumn(snapshot: snapshot, now: now)
                .frame(width: 560)
            VStack(alignment: .leading, spacing: 34) {
                TodayPanel(day: days[0], zone: zone, now: now)
                UpcomingGrid(days: Array(days.dropFirst()), zone: zone)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 96)
        .padding(.vertical, 64)
        .offset(drift)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(sky)
        .overlay(alignment: .topTrailing) {
            if let notice {
                Label(notice, systemImage: "exclamationmark.arrow.circlepath")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Palette.alert)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(.top, 36)
                    .padding(.trailing, 60)
            }
        }
        .environment(\.timeZone, zone)
    }

    /// Up to 10 points in each axis, a new spot every ten minutes.
    private var drift: CGSize {
        let slot = Int(now.timeIntervalSince1970 / 600)
        let x = Double((slot * 7) % 21) - 10
        let y = Double((slot * 13) % 21) - 10
        return CGSize(width: x, height: y)
    }

    /// Day sky between sunrise and sunset, night sky otherwise, and dusk for the half hour
    /// either side. Without sun times (no weather) the night sky.
    private var sky: some View {
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
            .ignoresSafeArea()
    }

    /// The Pi's sun times are for the day it fetched; carry them to *today* so a cache from
    /// yesterday evening does not paint today's morning as night.
    private func dayShift(_ date: Date, to today: CivilDate) -> TimeInterval {
        let from = CivilDate(date, in: zone).start(in: zone)
        return today.start(in: zone).timeIntervalSince(from)
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
                CurrentWeather(weather: weather, metric: snapshot.isMetric)
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

// MARK: - Agenda

private struct TodayPanel: View {
    let day: AgendaDay
    let zone: TimeZone
    let now: Date

    /// Rows that fit the panel at this size; the rest are counted.
    private static let maxRows = 6

    var body: some View {
        let upcoming = day.events.filter { $0.isAllDay || $0.end > now }
        let finished = day.events.count - upcoming.count
        VStack(alignment: .leading, spacing: 18) {
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
            ForEach(upcoming.prefix(Self.maxRows), id: \.self) { event in
                TodayRow(event: event, zone: zone, now: now)
            }
            if upcoming.count > Self.maxRows {
                Text("+\(upcoming.count - Self.maxRows) more")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Palette.faint)
            }
        }
        .padding(36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }
}

private struct TodayRow: View {
    let event: CalendarEvent
    let zone: TimeZone
    let now: Date

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
                if let location = event.location, !location.isEmpty {
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

private struct UpcomingGrid: View {
    let days: [AgendaDay]
    let zone: TimeZone

    var body: some View {
        Grid(horizontalSpacing: 24, verticalSpacing: 24) {
            ForEach(Array(stride(from: 0, to: days.count, by: 3)), id: \.self) { row in
                GridRow {
                    ForEach(days[row..<min(row + 3, days.count)]) { day in
                        DayCard(day: day, zone: zone)
                    }
                }
            }
        }
    }
}

private struct DayCard: View {
    let day: AgendaDay
    let zone: TimeZone

    private static let maxRows = 4

    var body: some View {
        let date = day.day.start(in: zone)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(date.formatted(Date.FormatStyle(timeZone: zone).weekday(.wide)))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Text(date.formatted(Date.FormatStyle(timeZone: zone).month(.abbreviated).day()))
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Palette.faint)
            }
            .padding(.bottom, 4)
            ForEach(day.birthdays, id: \.self) { birthday in
                BirthdayLine(birthday: birthday, size: 22)
            }
            if day.events.isEmpty && day.birthdays.isEmpty {
                Text("Free")
                    .font(.system(size: 22))
                    .foregroundStyle(Palette.faint)
            }
            let shown = Array(day.events.prefix(Self.maxRows))
            let labels = shown.map { $0.isAllDay ? "•" : compactTime($0.start) }
            // Every row reserves the width of this card's longest time, so the titles line up
            // and get the rest of the card.
            let widest = labels.max { $0.count < $1.count } ?? ""
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
                        .lineLimit(1)
                }
            }
            if day.events.count > Self.maxRows {
                HStack(spacing: 12) {
                    Text(widest).hidden()
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .monospacedDigit()
                    Text("+\(day.events.count - Self.maxRows) more")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Palette.faint)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// "9a", "11:30a", "2p": the cards are a third of the agenda wide, and a full "11:30 AM"
    /// column leaves a title a dozen characters.
    private func compactTime(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "a" : "p"
        return minute == 0 ? "\(twelve)\(suffix)" : String(format: "%d:%02d%@", twelve, minute, suffix)
    }
}

private struct BirthdayLine: View {
    let birthday: Birthday
    let size: CGFloat

    var body: some View {
        Label {
            Text(birthday.age.map { "\(birthday.name) turns \($0)" } ?? "\(birthday.name)'s birthday")
        } icon: {
            Image(systemName: "gift.fill").foregroundStyle(Palette.today)
        }
        .font(.system(size: size, weight: .semibold))
        .foregroundStyle(Palette.ink)
        .lineLimit(1)
    }
}
