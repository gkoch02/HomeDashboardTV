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
struct MoonView: Theme {
    let snapshot: Snapshot
    let now: Date

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
    }

    var backdrop: some View { Starfield().background(Color.black) }

    private func plate(moon: Moon, s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // Header: dateline, phase name, illumination.
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

            // The filmstrip: (day offset, radius, x offset from centre), as the panel lays it.
            let row: [(Int, CGFloat, CGFloat)] = [
                (-3, 24, -315), (-2, 29, -250), (-1, 34, -168),
                (0, 95, 0),
                (1, 34, 168), (2, 29, 250), (3, 24, 315),
            ]
            let cy: CGFloat = 205
            ForEach(row, id: \.0) { offset, r, x in
                if let day = moon.days[safe: offset + 3] {
                    MoonDisc(fraction: day.fraction, radius: r * s, halo: offset == 0)
                        .position(x: (400 + x) * s, y: cy * s)
                    if offset != 0 {
                        Text(weekday(day.date))
                            .font(.custom(MoonFace.body, size: 18 * s).weight(.bold))
                            .foregroundStyle(MoonInk.muted)
                            .position(x: (400 + x) * s, y: (cy + r + 16) * s)
                    }
                }
            }

            // A dotted rule under the row, star-flecked like the panel's.
            DottedRule()
                .frame(width: 520 * s, height: 6 * s)
                .position(x: 400 * s, y: 308 * s)

            // The data block.
            centred(y: 326, s: s) { dataLine(lunarLine(moon), s: s) }
            if let sun = sunWeatherLine {
                centred(y: 359, s: s) { dataLine(sun, s: s) }
            }
            centred(y: sunWeatherLine == nil ? 359 : 394, s: s) {
                Text(nextPhaseLine(moon))
                    .font(.custom(MoonFace.body, size: 26 * s).weight(.bold))
                    .foregroundStyle(MoonInk.text)
            }

            // The quote: the panel's own (prefix "moonphase-"), else the dashboard's.
            if let quote = moon.quote ?? snapshot.quote {
                VStack(spacing: 6 * s) {
                    Text("“\(quote.text)”")
                        .font(.custom(MoonFace.body, size: 22 * s).weight(.semibold).italic())
                        .foregroundStyle(MoonInk.muted)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text("— \(quote.author)")
                        .font(.custom(MoonFace.caps, size: 15 * s).weight(.bold))
                        .foregroundStyle(MoonInk.text)
                }
                .frame(width: 680 * s)
                .position(x: 400 * s, y: (sunWeatherLine == nil ? 410 : 440) * s)
            }
        }
    }

    // MARK: Layout helpers

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
