import DashboardCore
import SwiftUI

/// The Pi's `fuzzyclock` theme: the time in words ("twenty five to nine"), as large as it fits,
/// over the date, with a strip of the weather now, the next three days and the moon along the
/// bottom.
///
/// The words change every five minutes and cross-fade when they do. The minutes are set in
/// the theme's first accent, the hour in its second, as on the Pi's colour panel; on the TV
/// they glow on true black.
///
/// As the layout appears the words write themselves in, left to right, and the date and the
/// strip come up under them.
struct FuzzyClockView: Theme {
    let snapshot: Snapshot
    let now: Date

    /// The build-in: the words' wipe, then the rest, each 0 to 1.
    @State private var written = 0.0
    @State private var rest = 0.0

    private var zone: TimeZone { snapshot.timeZone }

    var body: some View {
        let phrase = FuzzyClock.phrase(now, in: zone)
        VStack(spacing: 0) {
            VStack(spacing: 34) {
                ZStack {
                    words(phrase)
                        .id(phrase)
                        .transition(.opacity)
                }
                // Only the words animate, and only when they change.
                .animation(.easeInOut(duration: 1.6), value: phrase)
                .wipe(written, softness: 0.35)
                Text(now.formatted(Date.FormatStyle(timeZone: zone).weekday(.wide)) + "  ·  "
                     + now.formatted(Date.FormatStyle(timeZone: zone).day().month(.wide)))
                    .font(.custom(Face.sans, size: 58))
                    .foregroundStyle(Ink.secondary)
                    .opacity(rest)
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Rectangle().fill(Ink.rule).frame(height: 1.5)
            if let weather = snapshot.sources.weather?.data {
                Banner(weather: weather, moon: snapshot.moon, isMetric: snapshot.isMetric, now: now, zone: zone)
                    .frame(height: 150)
                    .opacity(rest)
                    .offset(y: (1 - rest) * 24)
            }
        }
        .padding(.horizontal, 20)
        .onBuildIn(reset: { settled in written = settled ? 1 : 0; rest = written }) {
            withAnimation(.easeInOut(duration: 1.8).delay(0.1)) { written = 1 }
            withAnimation(.easeOut(duration: 0.8).delay(1.3)) { rest = 1 }
        }
    }

    private func words(_ phrase: String) -> some View {
        FuzzyClock.segments(phrase).reduce(Text("")) { line, segment in
            line + Text(segment.text).foregroundColor(Ink.colour(segment.ink))
        }
        .font(.custom(Face.sans, size: 230).weight(.bold))
        .kerning(-4)
        .lineLimit(1)
        .minimumScaleFactor(0.3)
    }

    var backdrop: some View { Color.black }
}

private enum Ink {
    static let text = Color(red: 0.94, green: 0.94, blue: 0.95)
    static let primary = Color.p3(0.97, 0.81, 0.30)
    static let secondary = Color.p3(0.58, 0.62, 0.96)
    static let faint = text.opacity(0.55)
    static let rule = text.opacity(0.18)

    static func colour(_ ink: FuzzyClock.Ink) -> Color {
        switch ink {
        case .primary: return primary
        case .plain: return text
        case .secondary: return secondary
        }
    }
}

private enum Face {
    static let sans = "DMSans-9ptRegular"
}

/// The weather now, the next three days and tonight's moon: the Pi's bottom strip.
private struct Banner: View {
    let weather: Weather
    let moon: Moon?
    let isMetric: Bool
    let now: Date
    let zone: TimeZone

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 22) {
                Image(systemName: WeatherSymbol.name(for: weather.currentIcon))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Ink.primary)
                    .font(.system(size: 64))
                Text("\(Int(weather.currentTemp.rounded()))°")
                    .font(.custom(Face.sans, size: 76).weight(.bold))
                    .foregroundStyle(Ink.text)
                VStack(alignment: .leading, spacing: 4) {
                    Text(weather.currentDescription.capitalized(with: .current))
                        .font(.custom(Face.sans, size: 30).weight(.semibold))
                        .foregroundStyle(Ink.text)
                    Text(details)
                        .font(.custom(Face.sans, size: 24))
                        .foregroundStyle(Ink.faint)
                }
                .padding(.leading, 14)
            }
            Spacer(minLength: 30)
            HStack(spacing: 48) {
                ForEach(days, id: \.self) { day in
                    HStack(spacing: 14) {
                        Image(systemName: WeatherSymbol.name(for: day.icon))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Ink.text)
                            .font(.system(size: 34))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(day.date.start(in: zone).formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated)))
                                .font(.custom(Face.sans, size: 24).weight(.semibold))
                                .foregroundStyle(Ink.text)
                            Text("\(Int(day.high.rounded()))°/\(Int(day.low.rounded()))°")
                                .font(.custom(Face.sans, size: 24))
                                .foregroundStyle(Ink.faint)
                        }
                    }
                }
            }
            if let fraction = moon?.today?.fraction {
                MoonDisc(fraction: fraction, radius: 26)
                    .padding(.leading, 56)
            }
        }
        .padding(.horizontal, 10)
    }

    /// "H 48° L 35° · Feels 38° · Wind 12 mph NW", leaving out what the weather lacks.
    private var details: String {
        var parts = ["H \(Int(weather.high.rounded()))°  L \(Int(weather.low.rounded()))°"]
        if let feels = weather.feelsLike { parts.append("Feels \(Int(feels.rounded()))°") }
        if let speed = weather.windSpeed {
            let compass = weather.windDeg.map { " " + Compass.point($0) } ?? ""
            parts.append("Wind \(Int(speed.rounded())) \(isMetric ? "m/s" : "mph")\(compass)")
        }
        return parts.joined(separator: "  ·  ")
    }

    /// The three days after today.
    private var days: [DayForecast] {
        let today = CivilDate(now, in: zone)
        return Array(weather.forecast.filter { $0.date > today }.sorted { $0.date < $1.date }.prefix(3))
    }
}
