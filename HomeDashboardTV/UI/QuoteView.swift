import DashboardCore
import SwiftUI

/// The Pi's `qotd` theme: the day's quote, set large in Playfair Display between oversized
/// quotation marks, over a strip of the weather now, the next three days and the moon.
///
/// The quote is the dashboard's (`quote` in `/api/dashboard`), so it changes when the Pi's
/// does. It is set as large as fits: SwiftUI shrinks the whole block together, so a short
/// line and a long paragraph both fill the plate at one size.
struct QuoteView: Theme {
    let snapshot: Snapshot
    let now: Date

    private var zone: TimeZone { snapshot.timeZone }

    var body: some View {
        VStack(spacing: 0) {
            quote
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Rectangle().fill(Ink.rule).frame(height: 1.5)
            if let weather = snapshot.sources.weather?.data {
                WeatherStrip(weather: weather, moon: snapshot.moon, isMetric: snapshot.isMetric, zone: zone)
                    .frame(height: 150)
            } else {
                Text("Weather unavailable")
                    .font(.custom(Face.sans, size: 28).weight(.semibold))
                    .foregroundStyle(Ink.faint)
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
            }
        }
        .padding(.horizontal, 20)
    }

    var backdrop: some View { Ink.plate }

    @ViewBuilder private var quote: some View {
        if let quote = snapshot.quote {
            ZStack {
                marks
                VStack(spacing: 44) {
                    Text(quote.text)
                        .font(.custom(Face.serif, size: 104))
                        .lineSpacing(10)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Ink.cream)
                        .minimumScaleFactor(0.35)
                    Text("— \(quote.author)")
                        .font(.custom(Face.serif, size: 46))
                        .foregroundStyle(Ink.ochre)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(.horizontal, 170)
                .padding(.vertical, 70)
            }
        } else {
            Text("No quote today")
                .font(.custom(Face.serif, size: 60))
                .foregroundStyle(Ink.faint)
        }
    }

    /// The open mark at the top left, the close at the bottom right, in the accent.
    private var marks: some View {
        ZStack {
            Text("\u{201C}")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Text("\u{201D}")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.bottom, -60)
        }
        .font(.custom(Face.serif, size: 300))
        .foregroundStyle(Ink.ochre.opacity(0.85))
        .padding(.top, -40)
    }
}

private enum Ink {
    static let plate = Color(red: 0.085, green: 0.080, blue: 0.075)
    static let cream = Color(red: 0.95, green: 0.93, blue: 0.88)
    static let faint = cream.opacity(0.55)
    static let rule = cream.opacity(0.3)
    static let ochre = Color(red: 0.90, green: 0.66, blue: 0.27)
}

private enum Face {
    /// Playfair Display Bold: the file names itself Regular (see project.yml).
    static let serif = "PlayfairDisplay-Regular"
    static let sans = "DMSans-9ptRegular"
}

/// The panel's banner: icon and temperature, the reading, three days ahead, the moon.
private struct WeatherStrip: View {
    let weather: Weather
    let moon: Moon?
    let isMetric: Bool
    let zone: TimeZone

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 20) {
                Image(systemName: WeatherSymbol.name(for: weather.currentIcon))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 60))
                Text("\(Int(weather.currentTemp.rounded()))°")
                    .font(.custom(Face.sans, size: 72).weight(.bold))
            }
            .frame(width: 330, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(weather.currentDescription.capitalized)
                    .font(.custom(Face.sans, size: 30).weight(.bold))
                Text("H \(Int(weather.high.rounded()))°   L \(Int(weather.low.rounded()))°")
                    .font(.custom(Face.sans, size: 25).weight(.semibold))
                if let details {
                    Text(details)
                        .font(.custom(Face.sans, size: 23).weight(.medium))
                        .foregroundStyle(Ink.faint)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 44) {
                ForEach(weather.forecast.prefix(3), id: \.date) { day in
                    HStack(spacing: 14) {
                        Image(systemName: WeatherSymbol.name(for: day.icon))
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 36))
                            .frame(width: 50)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(day.date.start(in: zone).formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated)))
                                .font(.custom(Face.sans, size: 23).weight(.bold))
                            Text("\(Int(day.high.rounded()))° / \(Int(day.low.rounded()))°")
                                .font(.custom(Face.sans, size: 23).weight(.medium))
                                .foregroundStyle(Ink.cream.opacity(0.8))
                        }
                    }
                }
            }
            if let fraction = moon?.today?.fraction {
                MoonDisc(fraction: fraction, radius: 30)
                    .padding(.leading, 56)
            }
        }
        .foregroundStyle(Ink.cream)
        .padding(.horizontal, 10)
    }

    private var details: String? {
        var parts: [String] = []
        if let feels = weather.feelsLike { parts.append("Feels \(Int(feels.rounded()))°") }
        if let speed = weather.windSpeed {
            var wind = "Wind \(Int(speed.rounded())) \(isMetric ? "m/s" : "mph")"
            if let deg = weather.windDeg { wind += " \(Compass.point(deg))" }
            parts.append(wind)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }
}
