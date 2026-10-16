import DashboardCore
import SwiftUI

/// The Pi's `weatherglass` theme: a Victorian deck of weather instruments.
///
/// A thermometer with its cold, comfortable and hot zones and the day's high and low; an
/// aneroid barometer, 950 to 1050 hPa under the banjo barometer's words, with a hollow trend
/// needle where the pressure stood one to 36 hours ago (the TV keeps those readings, as the Pi
/// keeps its own) and the change in words; a hygrometer and the UV index; and along the bottom
/// a wind compass, the sun's arc between sunrise and sunset, the moon and the air quality.
///
/// On paper the Pi engraves it in ink. Here it is black enamel in brass bezels, which an OLED
/// draws with the dials' faces dark and only the engraving lit; the needles swing to their
/// readings when the layout appears.
struct WeatherglassView: Theme {
    let snapshot: Snapshot
    let now: Date

    @Environment(DashboardStore.self) private var store

    private var zone: TimeZone { snapshot.timeZone }
    private var weather: Weather? { snapshot.sources.weather?.data }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let gap: CGFloat = 22
            let side = size.width * 0.205
            let heroHeight = size.height * 0.6
            VStack(spacing: gap) {
                Masthead(now: now, zone: zone, place: weather?.locationName)
                    .frame(height: size.height * 0.085)
                HStack(spacing: gap) {
                    Panel {
                        Thermometer(weather: weather, isMetric: snapshot.isMetric)
                    }
                    .frame(width: side)
                    Panel {
                        Barometer(pressure: weather?.pressure,
                                  previous: store.pressureHistory.previous(now: now),
                                  alert: weather?.alerts.first?.event)
                    }
                    VStack(spacing: gap) {
                        Panel { Hygrometer(humidity: weather.map { Double($0.humidity) }) }
                        Panel { SolarIndex(uv: weather?.uvIndex) }
                    }
                    .frame(width: side)
                }
                .frame(height: heroHeight)
                HStack(spacing: gap) {
                    Panel { WindCompass(weather: weather, isMetric: snapshot.isMetric) }
                        .frame(width: size.width * 0.15)
                    Panel { SunArc(snapshot: snapshot, now: now) }
                    Panel { MoonPorthole(moon: snapshot.moon) }
                        .frame(width: size.width * 0.17)
                    Panel { AirBadge(air: snapshot.sources.airQuality?.data) }
                        .frame(width: size.width * 0.15)
                }
            }
        }
    }

    var backdrop: some View { Ink.plate }
}

// MARK: - Inks and faces

private enum Ink {
    static let plate = Color(red: 0.03, green: 0.028, blue: 0.026)
    static let panel = Color(red: 0.055, green: 0.051, blue: 0.046)
    static let ivory = Color(red: 0.93, green: 0.89, blue: 0.80)
    static let faint = ivory.opacity(0.55)
    static let engraving = ivory.opacity(0.32)
    static let brass = Color(red: 0.86, green: 0.70, blue: 0.38)
    static let mercury = Color(red: 0.88, green: 0.22, blue: 0.18)
    static let cold = Color(red: 0.36, green: 0.56, blue: 0.92)
    static let comfort = Color(red: 0.36, green: 0.72, blue: 0.46)
    static let amber = Color(red: 0.97, green: 0.78, blue: 0.30)
    static let orange = Color(red: 0.96, green: 0.55, blue: 0.22)
    static let violet = Color(red: 0.62, green: 0.38, blue: 0.82)

    /// Polished brass round a bezel: light catching the top left and the lower right.
    static let brassRing = AngularGradient(colors: [
        Color(red: 0.98, green: 0.88, blue: 0.58), Color(red: 0.62, green: 0.45, blue: 0.18),
        Color(red: 0.90, green: 0.74, blue: 0.40), Color(red: 0.55, green: 0.40, blue: 0.16),
        Color(red: 0.98, green: 0.88, blue: 0.58),
    ], center: .center, startAngle: .degrees(-135), endAngle: .degrees(225))

    static let brassFace = LinearGradient(colors: [
        Color(red: 0.99, green: 0.89, blue: 0.60), Color(red: 0.80, green: 0.62, blue: 0.30),
        Color(red: 0.95, green: 0.80, blue: 0.48),
    ], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Enamel: a faint lift at the centre, black at the rim.
    static func enamel(_ radius: CGFloat) -> RadialGradient {
        RadialGradient(colors: [Color(red: 0.075, green: 0.072, blue: 0.07), .black],
                       center: .center, startRadius: 0, endRadius: radius)
    }
}

private enum Face {
    /// Engraved words, as on the Pi.
    static func engraved(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .custom("Cinzel", size: size).weight(weight)
    }

    /// Scale numerals and readings.
    static func numeral(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

/// A point on a dial at *degrees* (maths convention: anticlockwise from three o'clock).
private func onDial(_ centre: CGPoint, _ radius: CGFloat, _ degrees: Double) -> CGPoint {
    let a = degrees * .pi / 180
    return CGPoint(x: centre.x + radius * CGFloat(cos(a)), y: centre.y - radius * CGFloat(sin(a)))
}

// MARK: - Frame

private struct Panel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Ink.panel)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Ink.brass.opacity(0.55), lineWidth: 2)
            }
    }
}

private struct Nameplate: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Face.engraved(24))
            .foregroundStyle(Ink.faint)
            .tracking(2)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

/// The needles swing to their readings once the layout appears: 0 at rest, 1 on the reading.
/// Skipped under Reduce Motion.
private struct Swing: ViewModifier {
    @Binding var amount: Double
    let delay: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.onAppear {
            guard !reduceMotion else { amount = 1; return }
            DispatchQueue.main.async {
                withAnimation(.spring(response: 1.5, dampingFraction: 0.55).delay(delay)) { amount = 1 }
            }
        }
    }
}

// MARK: - Masthead

private struct Masthead: View {
    let now: Date
    let zone: TimeZone
    let place: String?

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                HStack {
                    Text(dateLine)
                    Spacer()
                    Text(rightLine)
                }
                .font(Face.engraved(30))
                .foregroundStyle(Ink.ivory.opacity(0.8))
                .tracking(2)
                HStack(spacing: 30) {
                    Image(systemName: "sparkle").font(.system(size: 26))
                    Text("WEATHERGLASS")
                        .font(Face.engraved(62, .bold))
                        .tracking(6)
                    Image(systemName: "sparkle").font(.system(size: 26))
                }
                .foregroundStyle(Ink.brassFace)
            }
            .frame(maxHeight: .infinity)
            VStack(spacing: 4) {
                Rectangle().fill(Ink.brass.opacity(0.7)).frame(height: 2.5)
                Rectangle().fill(Ink.brass.opacity(0.4)).frame(height: 1)
            }
        }
    }

    /// "OCT 15 · MMXXVI".
    private var dateLine: String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let month = now.formatted(Date.FormatStyle(timeZone: zone).month(.abbreviated)).uppercased()
        return "\(month) \(cal.component(.day, from: now)) · \(Roman.numeral(cal.component(.year, from: now)))"
    }

    private var rightLine: String {
        place?.uppercased() ?? now.formatted(Date.FormatStyle(timeZone: zone).weekday(.wide)).uppercased()
    }
}

private enum Roman {
    static func numeral(_ value: Int) -> String {
        let table: [(Int, String)] = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
                                      (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var n = value
        var out = ""
        for (v, s) in table {
            while n >= v { out += s; n -= v }
        }
        return out
    }
}

// MARK: - Thermometer

private struct Thermometer: View {
    let weather: Weather?
    let isMetric: Bool

    @State private var rise = 0.0

    var body: some View {
        let scale = Weatherglass.thermometer(isMetric: isMetric)
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Tube(scale: scale, temp: weather?.currentTemp, rise: rise)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let weather {
                    VStack(alignment: .leading, spacing: 14) {
                        reading("HIGH", weather.high)
                        reading("LOW", weather.low)
                        Rectangle().fill(Ink.engraving).frame(width: 100, height: 1.5).padding(.vertical, 6)
                        Text("\(Int(weather.currentTemp.rounded()))°")
                            .font(Face.numeral(84))
                            .foregroundStyle(Ink.ivory)
                            .minimumScaleFactor(0.6)
                        if let feels = weather.feelsLike {
                            Text("FEELS \(Int(feels.rounded()))°")
                                .font(Face.engraved(22))
                                .foregroundStyle(Ink.faint)
                        }
                    }
                    .fixedSize()
                }
            }
            Nameplate(text: "THERMOMETER · \(scale.symbol)")
        }
        .modifier(Swing(amount: $rise, delay: 0.3))
    }

    private func reading(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(Face.engraved(20)).foregroundStyle(Ink.faint)
            Text("\(Int(value.rounded()))°").font(Face.numeral(40)).foregroundStyle(Ink.ivory)
        }
    }
}

/// The glass tube and bulb with the mercury at the temperature, the scale on its left and the
/// zones on its right, a pointer at the reading. `rise` lifts the mercury from the bulb.
private struct Tube: View {
    let scale: Weatherglass.Scale
    let temp: Double?
    let rise: Double

    var body: some View {
        Canvas { context, size in
            let tubeX = size.width * 0.5
            let top: CGFloat = 16
            let bulbR = min(size.width * 0.16, 30)
            let bulbY = size.height - bulbR - 6
            let bottom = bulbY - bulbR * 0.9
            let tubeW = bulbR * 0.75
            func y(_ t: Double) -> CGFloat {
                let f = (min(max(t, scale.low), scale.high) - scale.low) / (scale.high - scale.low)
                return bottom - CGFloat(f) * (bottom - top - 10)
            }
            // The scale: a tick every unit of ten (or five), numerals at the majors.
            let step = (scale.high - scale.low) > 80 ? 5.0 : 2.5
            var t = scale.low
            while t <= scale.high + 0.01 {
                let major = scale.majors.contains(t)
                var tick = Path()
                tick.move(to: CGPoint(x: tubeX - tubeW / 2 - 6, y: y(t)))
                tick.addLine(to: CGPoint(x: tubeX - tubeW / 2 - (major ? 22 : 13), y: y(t)))
                context.stroke(tick, with: .color(major ? Ink.ivory.opacity(0.8) : Ink.engraving), lineWidth: major ? 2 : 1.2)
                if major {
                    context.draw(Text(verbatim: "\(Int(t))").font(Face.numeral(20)).foregroundStyle(Ink.ivory.opacity(0.85)),
                                 at: CGPoint(x: tubeX - tubeW / 2 - 30, y: y(t)), anchor: .trailing)
                }
                t += step
            }
            // The zones, in a band right of the tube.
            let bandX = tubeX + tubeW / 2 + 10
            func zone(_ lo: Double, _ hi: Double, _ colour: Color) {
                let rect = CGRect(x: bandX, y: y(hi), width: 10, height: y(lo) - y(hi))
                context.fill(Path(rect), with: .color(colour))
            }
            zone(scale.low, scale.high, Ink.ivory.opacity(0.08))
            zone(scale.low, scale.cold, Ink.cold.opacity(0.85))
            zone(scale.comfort.lowerBound, scale.comfort.upperBound, Ink.comfort.opacity(0.85))
            zone(scale.hot, scale.high, Ink.mercury.opacity(0.75))
            // The glass, then the mercury in it.
            let tube = Path(roundedRect: CGRect(x: tubeX - tubeW / 2, y: top - 6, width: tubeW, height: bottom - top + 20),
                            cornerRadius: tubeW / 2)
            context.fill(tube, with: .color(Ink.ivory.opacity(0.06)))
            context.stroke(tube, with: .color(Ink.ivory.opacity(0.5)), lineWidth: 2)
            let bulb = Path(ellipseIn: CGRect(x: tubeX - bulbR, y: bulbY - bulbR, width: bulbR * 2, height: bulbR * 2))
            context.fill(bulb, with: .color(Ink.mercury))
            context.stroke(bulb, with: .color(Ink.ivory.opacity(0.5)), lineWidth: 2)
            if let temp {
                let level = bottom + (y(temp) - bottom) * CGFloat(rise)
                let column = CGRect(x: tubeX - tubeW * 0.28, y: level, width: tubeW * 0.56, height: bulbY - level)
                context.fill(Path(roundedRect: column, cornerRadius: tubeW * 0.28), with: .color(Ink.mercury))
                // The pointer at the reading, on the zones.
                var pointer = Path()
                let py = y(temp)
                pointer.move(to: CGPoint(x: bandX + 14, y: py))
                pointer.addLine(to: CGPoint(x: bandX + 28, y: py - 9))
                pointer.addLine(to: CGPoint(x: bandX + 28, y: py + 9))
                pointer.closeSubpath()
                context.fill(pointer, with: .color(Ink.ivory))
            }
            // A highlight down the glass.
            var shine = Path()
            shine.move(to: CGPoint(x: tubeX - tubeW * 0.3, y: top + 4))
            shine.addLine(to: CGPoint(x: tubeX - tubeW * 0.3, y: bottom))
            context.stroke(shine, with: .color(.white.opacity(0.18)), lineWidth: 2)
        }
    }
}

// MARK: - Barometer

private struct Barometer: View {
    let pressure: Double?
    let previous: Double?
    let alert: String?

    @State private var swing = 0.0

    var body: some View {
        GeometryReader { geometry in
            // An alert takes a band across the top, and the dial shrinks below it.
            let band: CGFloat = alert == nil ? 0 : 56
            let d = min(geometry.size.width, geometry.size.height - band)
            let centre = CGPoint(x: geometry.size.width / 2, y: band + (geometry.size.height - band) / 2)
            ZStack {
                Dial(diameter: d, pressure: pressure, previous: previous)
                    .frame(width: d, height: d)
                    .position(centre)
                if let pressure {
                    let rest = Weatherglass.startDegrees
                    let angle = rest + (Weatherglass.angle(hPa: pressure) - rest) * swing
                    NeedleShape(degrees: angle, length: d * 0.36, tail: d * 0.09, width: d * 0.028)
                        .fill(Ink.brassFace)
                        .shadow(color: .black.opacity(0.6), radius: 6, x: 3, y: 5)
                        .frame(width: d, height: d)
                        .position(centre)
                }
                Circle()
                    .fill(Ink.brassFace)
                    .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 2))
                    .frame(width: d * 0.06, height: d * 0.06)
                    .position(centre)
                if let alert {
                    Text(alert.uppercased())
                        .font(Face.engraved(24, .bold))
                        .tracking(2)
                        .foregroundStyle(Ink.mercury)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Ink.panel))
                        .overlay(Capsule().strokeBorder(Ink.mercury.opacity(0.8), lineWidth: 2))
                        .position(x: centre.x, y: 20)
                }
            }
        }
        .modifier(Swing(amount: $swing, delay: 0.15))
    }
}

/// The barometer's bezel, enamel face, scale, words, reading and trend needle.
private struct Dial: View {
    let diameter: CGFloat
    let pressure: Double?
    let previous: Double?

    var body: some View {
        let d = diameter
        ZStack {
            Circle().fill(Ink.enamel(d / 2))
            Circle().strokeBorder(Ink.brassRing, lineWidth: d * 0.045)
            Circle().strokeBorder(Color.black.opacity(0.7), lineWidth: 2).padding(d * 0.045)
            Canvas { context, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let rim = d / 2 - d * 0.075
                // The scale: a tick every 2 hPa, longer every 10 with a numeral.
                for p in stride(from: 950, through: 1050, by: 2) {
                    let a = Weatherglass.angle(hPa: Double(p))
                    let major = p % 10 == 0
                    var tick = Path()
                    tick.move(to: onDial(c, rim, a))
                    tick.addLine(to: onDial(c, rim - (major ? d * 0.05 : d * 0.025), a))
                    context.stroke(tick, with: .color(major ? Ink.ivory : Ink.ivory.opacity(0.5)),
                                   lineWidth: major ? 2.5 : 1.3)
                    if major {
                        context.draw(Text(verbatim: "\(p)").font(Face.numeral(d * 0.036)).foregroundStyle(Ink.ivory),
                                     at: onDial(c, rim - d * 0.09, a))
                    }
                }
                var arc = Path()
                arc.addArc(center: c, radius: rim, startAngle: .degrees(-Weatherglass.startDegrees),
                           endAngle: .degrees(-(Weatherglass.startDegrees - Weatherglass.sweepDegrees)), clockwise: false)
                context.stroke(arc, with: .color(Ink.ivory.opacity(0.6)), lineWidth: 1.5)
                for (hPa, word) in Weatherglass.words {
                    context.draw(Text(word).font(Face.engraved(d * 0.034)).foregroundStyle(Ink.brass),
                                 at: onDial(c, rim * 0.54, Weatherglass.angle(hPa: hPa)))
                }
                // The trend needle: hollow, where the pressure stood.
                if let previous {
                    let needle = NeedleShape(degrees: Weatherglass.angle(hPa: previous), length: d * 0.33,
                                             tail: 0, width: d * 0.022).path(in: CGRect(origin: .zero, size: size))
                    context.stroke(needle, with: .color(Ink.brass.opacity(0.9)), lineWidth: 2)
                }
                let readingY = c.y + d * 0.2
                context.draw(Text(verbatim: pressure.map { "\(Int($0.rounded())) hPa" } ?? "—")
                    .font(Face.numeral(d * 0.058)).foregroundStyle(Ink.ivory), at: CGPoint(x: c.x, y: readingY))
                if let pressure, let word = Weatherglass.trend(pressure, from: previous) {
                    context.draw(Text(word).font(Face.engraved(d * 0.03)).foregroundStyle(trendColour(pressure)),
                                 at: CGPoint(x: c.x, y: readingY + d * 0.065))
                }
                context.draw(Text("BAROMETER").font(Face.engraved(d * 0.032)).foregroundStyle(Ink.faint),
                             at: CGPoint(x: c.x, y: c.y + d * 0.36))
            }
        }
    }

    private func trendColour(_ pressure: Double) -> Color {
        guard let previous else { return Ink.faint }
        if pressure - previous > 1 { return Ink.comfort }
        if pressure - previous < -1 { return Ink.cold }
        return Ink.faint
    }
}

/// A tapered needle from the centre of its rect: point at *length* along *degrees*, a tail
/// behind the pivot. Animatable, so it swings round the dial.
private struct NeedleShape: Shape {
    var degrees: Double
    let length: CGFloat
    let tail: CGFloat
    let width: CGFloat
    /// The pivot; the rect's centre when nil.
    var pivot: CGPoint? = nil

    var animatableData: Double {
        get { degrees }
        set { degrees = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let c = pivot ?? CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.move(to: onDial(c, length, degrees))
        p.addLine(to: onDial(c, width / 2, degrees + 90))
        p.addLine(to: onDial(c, tail, degrees + 180 - 8))
        p.addLine(to: onDial(c, tail, degrees + 180 + 8))
        p.addLine(to: onDial(c, width / 2, degrees - 90))
        p.closeSubpath()
        return p
    }
}

// MARK: - Hygrometer and solar index

private struct Hygrometer: View {
    let humidity: Double?

    @State private var swing = 0.0

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                let w = geometry.size.width
                let r = min(w / 2 - 20, geometry.size.height - 30)
                let c = CGPoint(x: w / 2, y: geometry.size.height - 10)
                ZStack {
                    Canvas { context, _ in
                        func angle(_ h: Double) -> Double { 180 - 180 * h / 100 }
                        var band = Path()
                        band.addArc(center: c, radius: r - 12, startAngle: .degrees(-angle(Weatherglass.comfortableHumidity.lowerBound)),
                                    endAngle: .degrees(-angle(Weatherglass.comfortableHumidity.upperBound)), clockwise: false)
                        context.stroke(band, with: .color(Ink.comfort.opacity(0.85)), lineWidth: 14)
                        var arc = Path()
                        arc.addArc(center: c, radius: r, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                        context.stroke(arc, with: .color(Ink.brass), lineWidth: 3)
                        for h in stride(from: 0, through: 100, by: 10) {
                            let a = angle(Double(h))
                            var tick = Path()
                            tick.move(to: onDial(c, r, a))
                            tick.addLine(to: onDial(c, r - (h % 20 == 0 ? 22 : 12), a))
                            context.stroke(tick, with: .color(Ink.ivory.opacity(0.8)), lineWidth: 1.6)
                            if h % 20 == 0 {
                                context.draw(Text(verbatim: "\(h)").font(Face.numeral(18)).foregroundStyle(Ink.ivory.opacity(0.85)),
                                             at: onDial(c, r + 18, a))
                            }
                        }
                    }
                    if let humidity {
                        NeedleShape(degrees: 180 - 180 * humidity / 100 * swing, length: r - 8, tail: 0, width: 10, pivot: c)
                            .fill(Ink.ivory)
                        Circle().fill(Ink.brassFace).frame(width: 18, height: 18).position(c)
                    }
                }
            }
            Text(humidity.map { "\(Int($0))%" } ?? "—")
                .font(Face.numeral(40))
                .foregroundStyle(Ink.ivory)
            Nameplate(text: "HYGROMETER")
        }
        .modifier(Swing(amount: $swing, delay: 0.45))
    }
}

/// The UV index on a scale of coloured cells, lit up to the reading.
private struct SolarIndex: View {
    let uv: Double?

    private static func colour(_ cell: Int) -> Color {
        switch cell {
        case ..<3: return Ink.comfort
        case ..<6: return Ink.amber
        case ..<8: return Ink.orange
        case ..<11: return Ink.mercury
        default: return Ink.violet
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            GeometryReader { geometry in
                let cells = 12
                let w = geometry.size.width / CGFloat(cells)
                let reading = uv ?? -1
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 3) {
                        ForEach(0..<cells, id: \.self) { cell in
                            Rectangle()
                                .fill(Self.colour(cell).opacity(Double(cell) <= reading.rounded() ? 0.95 : 0.2))
                                .frame(height: 30)
                        }
                    }
                    .offset(y: 22)
                    if let uv {
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Ink.ivory)
                            .position(x: (CGFloat(min(uv, 11.5)) + 0.5) * w, y: 8)
                    }
                    ForEach([0, 3, 6, 8, 11], id: \.self) { n in
                        Text("\(n)")
                            .font(Face.numeral(18))
                            .foregroundStyle(Ink.ivory.opacity(0.8))
                            .position(x: (CGFloat(n) + 0.5) * w, y: 70)
                    }
                }
            }
            .frame(height: 84)
            Text(uv.map { String(format: "%.1f · %@", $0, Weatherglass.uvCategory($0)) } ?? "—")
                .font(Face.numeral(30))
                .foregroundStyle(Ink.ivory)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Spacer(minLength: 0)
            Nameplate(text: "SOLAR INDEX")
        }
    }
}

// MARK: - The bottom row

private struct WindCompass: View {
    let weather: Weather?
    let isMetric: Bool

    @State private var swing = 0.0

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                let d = min(geometry.size.width, geometry.size.height)
                let c = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                ZStack {
                    Circle().fill(Ink.enamel(d / 2)).frame(width: d, height: d).position(c)
                    Circle().strokeBorder(Ink.brassRing, lineWidth: d * 0.07).frame(width: d, height: d).position(c)
                    ForEach(Array(["N", "E", "S", "W"].enumerated()), id: \.offset) { i, letter in
                        Text(letter)
                            .font(Face.engraved(d * 0.13, .bold))
                            .foregroundStyle(letter == "N" ? Ink.mercury : Ink.ivory.opacity(0.85))
                            .position(onDial(c, d * 0.31, 90 - Double(i) * 90))
                    }
                    if let deg = weather?.windDeg {
                        // A vane points into the wind: north is up, bearings run clockwise.
                        NeedleShape(degrees: 90 - deg * swing, length: d * 0.3, tail: d * 0.14, width: d * 0.07)
                            .fill(Ink.brassFace)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                        Circle().fill(Ink.brassFace).frame(width: d * 0.09, height: d * 0.09).position(c)
                    }
                }
            }
            Text(caption)
                .font(Face.numeral(26))
                .foregroundStyle(Ink.ivory)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .modifier(Swing(amount: $swing, delay: 0.6))
    }

    private var caption: String {
        guard let speed = weather?.windSpeed else { return "CALM" }
        let compass = weather?.windDeg.map { " " + Compass.point($0) } ?? ""
        return "\(Int(speed.rounded())) \(isMetric ? "m/s" : "mph")\(compass)"
    }
}

/// The sun's arc from sunrise to sunset, with the sun on it while it is up, over a horizon
/// bar lit for the daylight hours.
private struct SunArc: View {
    let snapshot: Snapshot
    let now: Date

    var body: some View {
        let zone = snapshot.timeZone
        let day = CivilDate(now, in: zone)
        let times = LightCycle.daylight(snapshot, sun: SunModel(snapshot: snapshot), on: day)
        VStack(spacing: 10) {
            Canvas { context, size in
                let barY = size.height - 14
                let dayStart = day.start(in: zone), dayLength = 86_400.0
                func x(_ t: Date) -> CGFloat { size.width * CGFloat(t.timeIntervalSince(dayStart) / dayLength) }
                let bar = CGRect(x: 0, y: barY, width: size.width, height: 12)
                context.fill(Path(roundedRect: bar, cornerRadius: 6), with: .color(Ink.ivory.opacity(0.12)))
                guard let (rise, set) = times else { return }
                let x0 = x(rise), x1 = x(set)
                context.fill(Path(roundedRect: CGRect(x: x0, y: barY, width: x1 - x0, height: 12), cornerRadius: 6),
                             with: .color(Ink.amber.opacity(0.75)))
                // The arc over the daylight.
                let r = min((x1 - x0) / 2, barY - 16)
                let c = CGPoint(x: (x0 + x1) / 2, y: barY)
                var arc = Path()
                arc.addArc(center: c, radius: r, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                context.stroke(arc, with: .color(Ink.brass.opacity(0.8)), style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                // Now: a tick on the bar, and the sun on the arc while it is up.
                let xn = x(now)
                var tick = Path()
                tick.move(to: CGPoint(x: xn, y: barY - 6))
                tick.addLine(to: CGPoint(x: xn, y: barY + 18))
                context.stroke(tick, with: .color(Ink.ivory), lineWidth: 2.5)
                if now > rise && now < set {
                    let f = now.timeIntervalSince(rise) / set.timeIntervalSince(rise)
                    let p = onDial(c, r, 180 - 180 * f)
                    let glow = Path(ellipseIn: CGRect(x: p.x - 30, y: p.y - 30, width: 60, height: 60))
                    context.fill(glow, with: .radialGradient(Gradient(colors: [Ink.amber.opacity(0.5), .clear]),
                                                              center: p, startRadius: 0, endRadius: 30))
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 14, y: p.y - 14, width: 28, height: 28)), with: .color(Ink.amber))
                }
            }
            HStack {
                if let (rise, set) = times {
                    Text("RISE \(CompactTime.string(rise, in: zone))")
                    Spacer()
                    Text("DAYLIGHT \(LightCycle.formatLength(set.timeIntervalSince(rise)).uppercased())")
                        .foregroundStyle(Ink.faint)
                    Spacer()
                    Text("SET \(CompactTime.string(set, in: zone))")
                } else {
                    Text("SUN TIMES UNAVAILABLE").foregroundStyle(Ink.faint)
                }
            }
            .font(Face.engraved(22))
            .foregroundStyle(Ink.ivory)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
    }
}

private struct MoonPorthole: View {
    let moon: Moon?

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                let d = min(geometry.size.width, geometry.size.height)
                ZStack {
                    if let day = moon?.today {
                        MoonDisc(fraction: day.fraction, radius: d * 0.42)
                    }
                    Circle().strokeBorder(Ink.brassRing, lineWidth: d * 0.07).frame(width: d, height: d)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let moon, let day = moon.today {
                Text(moon.phaseName.uppercased())
                    .font(Face.engraved(20))
                    .foregroundStyle(Ink.faint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("\(Int(day.illumination.rounded()))%")
                    .font(Face.numeral(24))
                    .foregroundStyle(Ink.ivory)
            }
        }
    }
}

private struct AirBadge: View {
    let air: AirQuality?

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                let d = min(geometry.size.width, geometry.size.height)
                ZStack {
                    Circle().fill(Ink.enamel(d / 2))
                    Circle().strokeBorder(air.map { colour($0.band) } ?? Ink.engraving, lineWidth: d * 0.1)
                    Circle().strokeBorder(Ink.brassRing, lineWidth: 3)
                    Text(air.map { "\($0.aqi)" } ?? "—")
                        .font(Face.numeral(d * 0.32))
                        .foregroundStyle(Ink.ivory)
                }
                .frame(width: d, height: d)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text("AIR · AQI")
                .font(Face.engraved(20))
                .foregroundStyle(Ink.faint)
            Text(air?.shortLabel.uppercased() ?? "NO READING")
                .font(Face.engraved(22, .bold))
                .foregroundStyle(Ink.ivory)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    /// The Pi's ring: green when good, brass when moderate, red when unhealthy for some, and
    /// ivory beyond.
    private func colour(_ band: AirQuality.Band) -> Color {
        switch band {
        case .good: return Ink.comfort
        case .moderate: return Ink.brass
        case .sensitive: return Ink.mercury
        default: return Ink.violet
        }
    }
}
