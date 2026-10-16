import DashboardCore
import SwiftUI

/// The Pi's `moonphase_photo` theme, drawn natively: today's moon from the real photograph,
/// cut by the true terminator with a faint earthshine copy on the dark side, three days
/// either side, then the panel's data block and its quote.
///
/// Composed on the Pi's 800x480 grid (`MoonPanel` coordinates in `src/render/components/
/// moonphase_panel.py`) and scaled to the screen, so the layout matches the panel and the
/// type, set in the panel's own faces, stays sharp at 4K. All moon values come from the Pi's
/// `moon` block; nothing astronomical is computed here.
///
/// As the layout appears, today's moon comes slowly out of the dark, growing and sharpening
/// into focus; once it has landed the days either side follow outward, and the words settle
/// in after them.
struct MoonView: Theme {
    let snapshot: Snapshot
    let now: Date

    @State private var build = MoonBuild.start

    private var zone: TimeZone { snapshot.timeZone }

    var body: some View {
        // The plate keeps inside the TV's safe area (overscan); only the stars run to the edge.
        GeometryReader { geometry in
            let s = min(geometry.size.width / 800, geometry.size.height / 480)
            ZStack {
                if let moon = snapshot.moon {
                    plate(moon: moon, s: s)
                        .frame(width: 800 * s, height: 480 * s)
                } else {
                    Text("This dashboard's Pi does not send moon data yet.\nUpdate HomeDashboard on the Pi to show the moon.")
                        .font(.custom(MoonFace.body, size: 30).weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(MoonInk.text)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onBuildIn(reset: { settled in build = settled ? .settled : .start }) {
            withAnimation(.timingCurve(0.3, 0, 0.2, 1, duration: 2.8).delay(0.2)) { build.days[0] = 1 }
            for ring in 1...3 {
                withAnimation(.easeOut(duration: 0.6).delay(2.6 + 0.2 * Double(ring))) { build.days[ring] = 1 }
            }
            withAnimation(.easeOut(duration: 0.8).delay(3.0)) { build.header = 1 }
            withAnimation(.easeInOut(duration: 0.8).delay(3.2)) { build.rule = 1 }
            withAnimation(.easeOut(duration: 0.8).delay(3.4)) { build.block = 1 }
        }
    }

    var backdrop: some View { Starfield().background(Color.black) }

    private func plate(moon: Moon, s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // Header: dateline, phase name, illumination.
            Group {
                centred(y: 20, s: s) {
                    Text(dateline.uppercased())
                        .font(.custom(MoonFace.caps, size: 17 * s).weight(.bold))
                        .tracking(1.2 * s)
                        .foregroundStyle(MoonInk.text)
                }
                centred(y: 52, s: s) {
                    Text("~ \(moon.phaseName) ~")
                        .font(.custom(MoonFace.fraktur, size: 30 * s))
                        .foregroundStyle(MoonInk.text)
                }
                centred(y: 78, s: s) {
                    Text(illuminationLine(moon))
                        .font(.custom(MoonFace.body, size: 18 * s).weight(.semibold))
                        .foregroundStyle(MoonInk.muted)
                }
            }
            .opacity(build.header)
            .offset(y: (1 - build.header) * -10 * s)

            // The filmstrip: (day offset, radius, x offset from centre), as the panel lays it.
            let row: [(Int, CGFloat, CGFloat)] = [
                (-3, 24, -315), (-2, 29, -250), (-1, 34, -168),
                (0, 95, 0),
                (1, 34, 168), (2, 29, 250), (3, 24, 315),
            ]
            let cy: CGFloat = 205
            ForEach(row, id: \.0) { offset, r, x in
                if let day = moon.days[safe: offset + 3] {
                    let shown = build.days[abs(offset)]
                    // Today's grows from further back and comes into focus; the rest just fade up.
                    let today = offset == 0
                    MoonDisc(fraction: day.fraction, radius: r * s, halo: today)
                        .scaleEffect(today ? 0.72 + 0.28 * shown : 0.9 + 0.1 * shown)
                        .blur(radius: today ? (1 - shown) * 14 * s : 0)
                        .opacity(today ? min(1, shown * 1.6) : shown)
                        .position(x: (400 + x) * s, y: cy * s)
                    if offset != 0 {
                        Text(weekday(day.date))
                            .font(.custom(MoonFace.body, size: 18 * s).weight(.bold))
                            .foregroundStyle(MoonInk.muted)
                            .opacity(shown)
                            .position(x: (400 + x) * s, y: (cy + r + 16) * s)
                    }
                }
            }

            // A dotted rule under the row, star-flecked like the panel's.
            DottedRule()
                .frame(width: 520 * s, height: 6 * s)
                .mask { Rectangle().scaleEffect(x: build.rule, y: 1) }
                .position(x: 400 * s, y: 308 * s)

            // The data block and the quote, flowing down from the rule as the panel sets them:
            // one gap, the same between every line, as wide as the room under the rule allows
            // (4 to 26 pt), so a two-line quote pushes nothing into the line above it.
            VStack(spacing: 0) {
                dataLine(lunarLine(moon), s: s)
                gap(s)
                if let sun = sunWeatherLine {
                    dataLine(sun, s: s)
                    gap(s)
                }
                Text(nextPhaseLine(moon))
                    .font(.custom(MoonFace.body, size: 26 * s).weight(.bold))
                    .foregroundStyle(MoonInk.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                // The quote: the panel's own (prefix "moonphase-"), else the dashboard's.
                if let quote = moon.quote ?? snapshot.quote {
                    gap(s)
                    Text("“\(quote.text)”")
                        .font(.custom(MoonFace.body, size: 22 * s).weight(.semibold).italic())
                        .foregroundStyle(MoonInk.muted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2 * s)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .frame(width: 680 * s)
                        .fixedSize(horizontal: false, vertical: true)
                    gap(s)
                    Text("— \(quote.author)")
                        .font(.custom(MoonFace.caps, size: 15 * s).weight(.bold))
                        .foregroundStyle(MoonInk.text)
                        .lineLimit(1)
                }
            }
            .frame(width: 760 * s, height: (480 - Self.blockTop) * s, alignment: .top)
            .opacity(build.block)
            .offset(y: (1 - build.block) * 12 * s)
            .position(x: 400 * s, y: (480 + Self.blockTop) / 2 * s)
        }
    }

    // MARK: Layout helpers

    /// Where the data block starts, just under the dotted rule (y 308).
    private static let blockTop: CGFloat = 314

    /// The block's even gap: every one grows alike to share the room left under the rule.
    private func gap(_ s: CGFloat) -> some View {
        Spacer(minLength: 4 * s).frame(maxHeight: 26 * s)
    }

    private func centred<Content: View>(y: CGFloat, s: CGFloat, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 760 * s)
            .position(x: 400 * s, y: y * s)
    }

    private func dataLine(_ text: String, s: CGFloat) -> some View {
        Text(text)
            .font(.custom(MoonFace.body, size: 26 * s).weight(.semibold))
            .foregroundStyle(MoonInk.text)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    // MARK: Text, as the panel words it

    /// "Wednesday, October 14th, 2026", built part by part: a combined format style
    /// reorders weekday and month.
    private var dateline: String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let day = cal.component(.day, from: now)
        let weekday = now.formatted(Date.FormatStyle(timeZone: zone).weekday(.wide))
        let month = now.formatted(Date.FormatStyle(timeZone: zone).month(.wide))
        let year = cal.component(.year, from: now)
        return "\(weekday), \(month) \(day)\(ordinal(day)), \(year)"
    }

    private func ordinal(_ n: Int) -> String {
        if (11...13).contains(n % 100) { return "th" }
        switch n % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }

    private func illuminationLine(_ moon: Moon) -> String {
        let pct = Int((moon.today?.illumination ?? 0).rounded())
        return moon.supermoon ? "\(pct)% illuminated  ·  Supermoon" : "\(pct)% illuminated"
    }

    private func weekday(_ day: CivilDate) -> String {
        day.start(in: zone).formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated))
    }

    private func lunarLine(_ moon: Moon) -> String {
        var parts: [String] = []
        if let rise = moon.rise { parts.append("moonrise \(CompactTime.string(rise, in: zone))") }
        if let set = moon.set { parts.append("moonset \(CompactTime.string(set, in: zone))") }
        if let age = moon.today?.ageDays { parts.append(String(format: "age %.1fd", age)) }
        return parts.joined(separator: "  ~  ")
    }

    private var sunWeatherLine: String? {
        guard let weather = snapshot.sources.weather?.data else { return nil }
        var parts: [String] = []
        if let rise = weather.sunrise { parts.append("sunrise \(CompactTime.string(rise, in: zone))") }
        if let set = weather.sunset { parts.append("sunset \(CompactTime.string(set, in: zone))") }
        parts.append("\(Int(weather.currentTemp.rounded()))° \(weather.currentDescription.capitalized)")
        return parts.joined(separator: "  ~  ")
    }

    private func nextPhaseLine(_ moon: Moon) -> String {
        let label = moon.next.isFull ? "Full Moon" : "New Moon"
        let days = moon.next.days == 1 ? "1 day" : "\(moon.next.days) days"
        let when = moon.next.date.start(in: zone)
            .formatted(Date.FormatStyle(timeZone: zone).month(.abbreviated).day())
        return "Next \(label) in \(days)  ~  \(when)"
    }
}

/// The panel's faces, bundled from HomeDashboard's fonts/ (OFL).
private enum MoonFace {
    static let caps = "Cinzel"
    static let body = "Cormorant Garamond"
    static let fraktur = "Manufacturing Consent"
}

private enum MoonInk {
    static let text = Color(white: 0.94)
    static let muted = Color(white: 0.74)
}

/// Dots with a small four-point star every so often.
private struct DottedRule: View {
    var body: some View {
        Canvas { context, size in
            let y = size.height / 2
            let step = size.height * 1.4
            var x: CGFloat = 0
            var i = 0
            while x <= size.width {
                if i % 12 == 6 {
                    let r = size.height * 0.5
                    var star = Path()
                    star.move(to: CGPoint(x: x, y: y - r))
                    star.addLine(to: CGPoint(x: x + r * 0.25, y: y))
                    star.addLine(to: CGPoint(x: x, y: y + r))
                    star.addLine(to: CGPoint(x: x - r * 0.25, y: y))
                    star.closeSubpath()
                    star.move(to: CGPoint(x: x - r, y: y))
                    star.addLine(to: CGPoint(x: x, y: y - r * 0.25))
                    star.addLine(to: CGPoint(x: x + r, y: y))
                    star.addLine(to: CGPoint(x: x, y: y + r * 0.25))
                    star.closeSubpath()
                    context.fill(star, with: .color(MoonInk.muted))
                } else {
                    let d = size.height * 0.28
                    context.fill(Path(ellipseIn: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)),
                                 with: .color(MoonInk.muted.opacity(0.8)))
                }
                x += step
                i += 1
            }
        }
    }
}

/// How far the build-in has got, each part 0 to 1: the discs by distance from today (0 is
/// today), the header, the dotted rule drawing out from its middle, and the data block.
private struct MoonBuild {
    var days: [Double]
    var header: Double
    var rule: Double
    var block: Double

    static let start = MoonBuild(days: [0, 0, 0, 0], header: 0, rule: 0, block: 0)
    static let settled = MoonBuild(days: [1, 1, 1, 1], header: 1, rule: 1, block: 1)
}
