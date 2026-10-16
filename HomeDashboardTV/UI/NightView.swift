import DashboardCore
import SwiftUI

/// The Pi's `wide_night` theme, for after dark: four marks and nothing else (the moon's
/// phase, the temperature, the air-quality index and the sky), spaced evenly across the
/// screen's midline, each with a tracked label beneath.
///
/// The panel's red ground would light a dark room, so this is its inverse,
/// `wide_night_invert`: dim red marks on black. The moon is its lit part alone, with no
/// outline on the dark limb, and is spaced by that part, as on the panel. A mark
/// without data is dropped and the rest re-spaced; every mark shares one height, the
/// tallest at which the row fits.
struct NightView: Theme {
    let snapshot: Snapshot
    let now: Date

    var body: some View {
        GeometryReader { geometry in
            let cap = geometry.size.height * 0.42
            ViewThatFits(in: .horizontal) {
                ForEach([1.0, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4], id: \.self) { scale in
                    row(height: cap * scale)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    var backdrop: some View { Color.black }

    private enum Mark: Hashable {
        case moon(Double), number(String), sky(String)
    }

    private var marks: [(mark: Mark, label: String)] {
        var out: [(Mark, String)] = []
        if let fraction = snapshot.moon?.today?.fraction { out.append((.moon(fraction), "MOON")) }
        let weather = snapshot.sources.weather?.data
        if let weather { out.append((.number("\(Int(weather.currentTemp.rounded()))°"), "TEMP")) }
        if let aqi = snapshot.sources.airQuality?.data?.aqi { out.append((.number("\(aqi)"), "AQI")) }
        if let weather { out.append((.sky(WeatherSymbol.name(for: weather.currentIcon)), "SKY")) }
        return out
    }

    /// The marks at *height*, with gaps of at least half that between them and at the ends.
    private func row(height: CGFloat) -> some View {
        let gap = max(48, height * 0.5)
        return HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: gap)
            ForEach(marks, id: \.label) { item in
                VStack(spacing: 34) {
                    mark(item.mark, height: height)
                        .frame(height: height)
                    Text(item.label)
                        .font(.custom(Face.label, size: 28).weight(.heavy))
                        .tracking(28 * 0.4)
                        .foregroundStyle(Ink.mark.opacity(0.85))
                }
                .fixedSize()
                Spacer(minLength: gap)
            }
        }
    }

    @ViewBuilder private func mark(_ mark: Mark, height: CGFloat) -> some View {
        switch mark {
        case .moon(let fraction):
            // The row spaces the lit part, not the whole disc, so the gaps read even: the
            // terminator meets the midline at cos(2πf) of the radius, so the lit part spans
            // (1 − cos 2πf) of it, on the right while waxing.
            let lit = (1 - cos(2 * .pi * fraction)) / 2 * height
            LitShape(fraction: fraction)
                .fill(Ink.mark)
                .frame(width: height, height: height)
                .frame(width: lit, alignment: fraction.truncatingRemainder(dividingBy: 1) < 0.5 ? .trailing : .leading)
        case .number(let text):
            // Jura's figures stand 0.633 of the size, and sit 0.057 of it below the
            // line box's centre: sized and lifted so the digits alone span the height.
            let size = height / 0.633
            Text(text)
                .font(.custom(Face.numeral, size: size).weight(.semibold))
                .foregroundStyle(Ink.mark)
                .offset(y: -0.057 * size)
                .frame(height: height)
        case .sky(let symbol):
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .fontWeight(.medium)
                .foregroundStyle(Ink.mark)
                .frame(height: height)
        }
    }
}

private enum Ink {
    /// Dim enough to leave a dark room dark.
    static let mark = Color(red: 0.78, green: 0.13, blue: 0.10)
}

private enum Face {
    static let numeral = "Jura-Light"
    static let label = "Oxanium-ExtraLight"
}
