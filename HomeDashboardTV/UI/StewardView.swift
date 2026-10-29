import DashboardCore
import SwiftUI

/// A pair of layouts for two displays side by side, in Seneschal's HUD language (itself
/// Uplink's look without its motion): gold on navy, condensed Saira caps, slab panels with one
/// bevelled corner, sections headed by a short run, and the lit colour meaning one thing, here
/// what is under way now. Still, but for the clock.
///
/// The two split the day rather than repeat it. The wing, on the display beside, is now: the
/// clock, the date, the next thing on the calendar, and the sky as three quiet marks, set
/// against its inner edge. The main display, `StewardView`, is what is ahead: the next day as
/// a strip running away from the wing across the whole width (the main display is often the
/// wider), the agenda, the conditions and as many days of outlook as the width holds.
/// A gold rule runs off each one's inner edge at its header, so the pair reads across the gap.
/// Which edge is inner comes from `\.partnerEdge`; with none, the wing is taken to sit left of
/// the main display.
///
/// Both lay out 1080 points tall and as wide as the screen's shape makes that, scaled by `u`
/// from the environment rather than `scaleEffect`, which blurs text.
struct StewardView: Theme {
    let snapshot: Snapshot
    let now: Date

    static let fullBleed = true

    @Environment(\.partnerEdge) private var partnerEdge

    var body: some View {
        GeometryReader { g in
            let u = min(g.size.width / 1920, g.size.height / 1080)
            let width = g.size.width / max(u, 0.01)
            screen(width: width, u: u)
                .environment(\.stewardUnit, u)
                .frame(width: g.size.width, height: 1080 * u, alignment: .topLeading)
                .frame(width: g.size.width, height: g.size.height)
        }
    }

    var backdrop: some View { Ground(dim: false) }

    func notice(_ text: String) -> some View { StewardNotice(text: text) }

    private static let margin: CGFloat = 64

    private func screen(width: CGFloat, u: CGFloat) -> some View {
        let inner = width - 2 * Self.margin
        let wing = partnerEdge ?? .leading
        return VStack(alignment: .leading, spacing: 0) {
            MainHeader(snapshot: snapshot, now: now, wing: wing)
                .frame(height: 112 * u)
            Strip(snapshot: snapshot, now: now, width: inner)
                .frame(height: 340 * u)
                .padding(.top, 26 * u)
            HStack(alignment: .top, spacing: 48 * u) {
                AgendaColumn(snapshot: snapshot, now: now)
                    .frame(width: 560 * u)
                Conditions(snapshot: snapshot, now: now)
                    .frame(width: 600 * u)
                Outlook(snapshot: snapshot, now: now, width: inner - 560 - 600 - 96)
            }
            .padding(.top, 30 * u)
            .frame(height: 510 * u, alignment: .top)
            Spacer(minLength: 0)
            Dispatch(quote: snapshot.quote ?? snapshot.moon?.quote)
                .padding(.bottom, 34 * u)
        }
        .padding(.horizontal, Self.margin * u)
    }
}

/// The wing of the Steward pair: now, for the display beside the main one. See `StewardView`.
struct StewardWingView: Theme {
    let snapshot: Snapshot
    let now: Date

    static let fullBleed = true

    @Environment(\.partnerEdge) private var partnerEdge

    var body: some View {
        GeometryReader { g in
            let u = min(g.size.width / 1920, g.size.height / 1080)
            screen(height: g.size.height / max(u, 0.01), u: u)
                .environment(\.stewardUnit, u)
                .frame(width: g.size.width, height: g.size.height)
        }
    }

    var backdrop: some View { Ground(dim: true) }

    func notice(_ text: String) -> some View { StewardNotice(text: text) }

    private func screen(height: CGFloat, u: CGFloat) -> some View {
        let inner = partnerEdge ?? .trailing
        let align: HorizontalAlignment = inner == .trailing ? .trailing : .leading
        let zone = snapshot.timeZone
        let parts = ClockTime.parts(now, in: zone)
        return VStack(alignment: align, spacing: 0) {
            WingHeader(snapshot: snapshot, inner: inner)
                .frame(height: 112 * u)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 22 * u) {
                Text(parts.time)
                    .font(Face.wide(236 * u))
                    .foregroundStyle(Ink.goldHot)
                    .shadow(color: Ink.gold.opacity(0.45), radius: 24 * u)
                if let period = parts.period {
                    Text(period)
                        .font(Face.wide(58 * u))
                        .foregroundStyle(Ink.gold)
                }
            }
            .fixedSize()
            Caps(text: now.formatted(Date.FormatStyle(timeZone: zone).weekday(.wide).month(.wide).day()),
                 size: 34, colour: Ink.blue, tracking: 0.3)
                .padding(.top, 12 * u)
            NextUp(snapshot: snapshot, now: now, align: align)
                .frame(width: 860 * u)
                .padding(.top, 84 * u)
            Spacer(minLength: 0)
            Marks(snapshot: snapshot, inner: inner)
                .padding(.bottom, 64 * u)
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: align, vertical: .center))
        .padding(.horizontal, 96 * u)
        .frame(height: height * u)
    }
}

extension EnvironmentValues {
    /// Points on screen per point of Steward's 1080-point-tall layout.
    @Entry fileprivate var stewardUnit: CGFloat = 1
}

// MARK: - Inks, faces, shapes

/// Seneschal's dark look.
private enum Ink {
    /// The lit colour: under way now, and the wordmark.
    static let gold = p3(0xDE, 0xB0, 0x47)
    static let goldHot = p3(0xF6, 0xD2, 0x72)
    static let deep = rgb(0x02, 0x07, 0x0E)
    static let navy = rgb(0x05, 0x12, 0x20)
    /// Actions, labels and what is next: never on.
    static let blue = p3(0x7F, 0xC4, 0xF0)
    static let white = rgb(0xE4, 0xEE, 0xF5)
    /// Text, at 4.5:1 or more on the navy.
    static let muted = rgb(0x6E, 0x8D, 0xA6)
    /// Too faint for text: rules and edges.
    static let dim = rgb(0x34, 0x50, 0x6A)
    static let red = p3(0xFF, 0x5E, 0x55)

    static func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    /// A hero ink, in Display P3 (`WideColour.swift`).
    static func p3(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color.p3(Double(r) / 255, Double(g) / 255, Double(b) / 255)
    }
}

private enum Face {
    /// Michroma, for the wordmark, the clock and the big numbers.
    static func wide(_ size: CGFloat) -> Font { .custom("Michroma-Regular", size: size) }

    /// Saira condensed, for the interface.
    static func cond(_ size: CGFloat, _ weight: CGFloat = 500) -> Font { saira(size, weight: weight, width: 72) }

    /// Saira at full width, for reading.
    static func text(_ size: CGFloat, _ weight: CGFloat = 400) -> Font { saira(size, weight: weight, width: 100) }

    private static let weightAxis = 0x7767_6874 // 'wght'
    private static let widthAxis = 0x7764_7468 // 'wdth'
    private static var cache: [String: Font] = [:]

    /// Saira's variable font through its weight and width axes: its default instance is the
    /// Thin, so every weight goes through the axis.
    private static func saira(_ size: CGFloat, weight: CGFloat, width: CGFloat) -> Font {
        let key = "\(size)|\(weight)|\(width)"
        if let f = cache[key] { return f }
        let f = Font.descriptor([
            kCTFontNameAttribute: "Saira-Thin",
            kCTFontVariationAttribute: [weightAxis: weight, widthAxis: width],
        ], size: size)
        cache[key] = f
        return f
    }
}

/// Interface caps in condensed Saira, widely tracked.
private struct Caps: View {
    let text: String
    var size: CGFloat
    var weight: CGFloat = 600
    var colour = Ink.muted
    var tracking: CGFloat = 0.2
    @Environment(\.stewardUnit) private var u

    var body: some View {
        Text(text.uppercased())
            .font(Face.cond(size * u, weight))
            .tracking(size * u * tracking)
            .foregroundStyle(colour)
            .lineLimit(1)
    }
}

/// A rect with its bottom-right corner cut at 45°.
private struct Bevelled: Shape {
    var cut: CGFloat

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - min(cut, r.height, r.width)))
        p.addLine(to: CGPoint(x: r.maxX - min(cut, r.height, r.width), y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// A section's label: a short run in the quiet blue, the name, and a detail at the right.
private struct SectionLabel: View {
    let title: String
    var detail: String?
    @Environment(\.stewardUnit) private var u

    var body: some View {
        HStack(spacing: 14 * u) {
            Rectangle().fill(Ink.muted.opacity(0.7)).frame(width: 18 * u, height: 2.5 * u)
            Caps(text: title, size: 19, colour: Ink.white.opacity(0.72))
            Spacer(minLength: 0)
            if let detail { Caps(text: detail, size: 16, weight: 500, colour: Ink.muted) }
        }
        .frame(height: 30 * u)
    }
}

/// Seneschal's panel. Lit (under way), an outline in gold glowing into a faint fill of it with
/// a marker down the left edge; next, the same in the quiet blue without the glow; otherwise
/// a quiet slab that still reads plainly as there. Red when something needs attention.
private struct Panel: View {
    enum Tone { case quiet, next, lit, urgent }

    var tone = Tone.quiet
    var cut: CGFloat = 14
    @Environment(\.stewardUnit) private var u

    var body: some View {
        let shape = Bevelled(cut: cut * u)
        let ink: Color? = switch tone {
        case .quiet: nil
        case .next: Ink.blue
        case .lit: Ink.gold
        case .urgent: Ink.red
        }
        ZStack(alignment: .leading) {
            if let ink {
                shape.fill(LinearGradient(colors: [ink.opacity(tone == .next ? 0.07 : 0.11), ink.opacity(0.025)],
                                          startPoint: .leading, endPoint: .trailing))
                Rectangle().fill(ink).frame(width: 3.5 * u)
            } else {
                shape.fill(Color.white.opacity(0.04))
            }
        }
        .clipShape(shape)
        .overlay(shape.stroke(ink.map { $0.opacity(tone == .next ? 0.6 : 0.9) } ?? .white.opacity(0.1), lineWidth: 1.2 * u))
        .shadow(color: tone == .lit || tone == .urgent ? (ink ?? .clear).opacity(0.35) : .clear, radius: 10 * u)
    }
}

/// The rule under a header: a hairline across the screen and past its edges, so the burn-in
/// drift never pulls it short, with a gold run off the edge toward the other display.
private struct BridgeRule: View {
    let toward: HorizontalEdge
    var run: CGFloat = 300
    /// How far past the plate's margin the rule runs.
    var bleed: CGFloat
    @Environment(\.stewardUnit) private var u

    var body: some View {
        ZStack(alignment: toward == .leading ? .leading : .trailing) {
            Rectangle().fill(.white.opacity(0.13)).frame(height: 1.2 * u)
            Rectangle()
                .fill(LinearGradient(colors: [Ink.gold, Ink.gold.opacity(0.0)],
                                     startPoint: toward == .leading ? .leading : .trailing,
                                     endPoint: toward == .leading ? .trailing : .leading))
                .frame(width: (run + bleed) * u, height: 3 * u)
                .shadow(color: Ink.gold.opacity(0.7), radius: 6 * u)
        }
        .padding(.horizontal, -bleed * u)
    }
}

/// "9:30 AM" or "21:30", in the zone.
private func clock(_ date: Date, _ zone: TimeZone) -> String {
    let p = ClockTime.parts(date, in: zone)
    return p.period.map { "\(p.time) \($0)" } ?? p.time
}

/// "3 PM" or "15", in the zone.
private func hour(_ date: Date, _ zone: TimeZone) -> String {
    let p = ClockTime.parts(date, in: zone)
    let h = String(p.time.split(separator: ":").first ?? "")
    return p.period.map { "\(h) \($0)" } ?? h
}

private func degrees(_ v: Double) -> String { "\(Int(v.rounded()))°" }

/// Seneschal's ground: the navy, a haze of blue at the top, a faint warmth lower down,
/// scanlines and a vignette. The wing's is darker, for a display seen from the side.
private struct Ground: View {
    let dim: Bool

    var body: some View {
        Canvas { gc, size in
            let r = CGRect(origin: .zero, size: size)
            let u = min(size.width / 1920, size.height / 1080)
            gc.fill(Path(r), with: .linearGradient(Gradient(colors: [dim ? Ink.deep : Ink.navy, Ink.deep]),
                                                   startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            gc.fill(Path(r), with: .radialGradient(Gradient(colors: [Ink.blue.opacity(dim ? 0.06 : 0.11), Ink.blue.opacity(0.02), .clear]),
                                                   center: CGPoint(x: size.width * 0.5, y: 0),
                                                   startRadius: 0, endRadius: max(size.width * 0.45, size.height * 0.6)))
            gc.fill(Path(r), with: .radialGradient(Gradient(colors: [Ink.gold.opacity(dim ? 0.035 : 0.05), .clear]),
                                                   center: CGPoint(x: size.width * 0.5, y: size.height * 0.7),
                                                   startRadius: 0, endRadius: max(size.width * 0.3, size.height * 0.45)))
            var scan = Path()
            let step = 3 * max(u, 1)
            var y: CGFloat = 0
            while y < size.height {
                scan.addRect(CGRect(x: 0, y: y, width: size.width, height: step / 3))
                y += step
            }
            gc.fill(scan, with: .color(.black.opacity(0.16)))
            gc.fill(Path(r), with: .radialGradient(Gradient(colors: [.clear, Ink.deep.opacity(dim ? 0.9 : 0.8)]),
                                                   center: CGPoint(x: size.width / 2, y: size.height / 2),
                                                   startRadius: size.height * 0.4, endRadius: max(size.width, size.height) * 0.62))
        }
        .background(Ink.deep)
    }
}

/// The corner line, as Seneschal says something needs attention: a red marker and caps.
private struct StewardNotice: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Ink.red).frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text("NEEDS ATTENTION").font(Face.cond(17, 700)).tracking(17 * 0.22).foregroundStyle(Ink.red)
                Text(text).font(Face.text(20)).foregroundStyle(Ink.white.opacity(0.9))
            }
        }
        .fixedSize()
        .padding(.trailing, 22)
        .padding(.vertical, 10)
        .background(LinearGradient(colors: [Ink.red.opacity(0.2), Ink.red.opacity(0.02)], startPoint: .leading, endPoint: .trailing))
    }
}

// MARK: - The main display's header

/// The wordmark, Seneschal's check line (the Pi's sources all current, or which are not), and
/// the date and time, over the bridge rule.
private struct MainHeader: View {
    let snapshot: Snapshot
    let now: Date
    let wing: HorizontalEdge
    @Environment(\.stewardUnit) private var u

    var body: some View {
        let zone = snapshot.timeZone
        let stale = Steward.stale(snapshot.sources)
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: 0) {
                Text("STEWARD")
                    .font(Face.wide(40 * u))
                    .foregroundStyle(Ink.gold)
                    .shadow(color: Ink.gold.opacity(0.45), radius: 10 * u)
                    .fixedSize()
                HStack(spacing: 12 * u) {
                    Image(systemName: stale.isEmpty ? "checkmark.seal" : "exclamationmark.triangle")
                        .font(.system(size: 22 * u, weight: .medium))
                        .foregroundStyle(stale.isEmpty ? Ink.blue : Ink.red)
                    Caps(text: (stale.isEmpty ? "All as expected" : stale.joined(separator: ", ") + " stale")
                         + " · synced " + clock(snapshot.generatedAt, zone),
                         size: 18, colour: stale.isEmpty ? Ink.blue.opacity(0.85) : Ink.red, tracking: 0.18)
                }
                .padding(.leading, 56 * u)
                Spacer(minLength: 24 * u)
                Caps(text: now.formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated).month(.abbreviated).day())
                     + "  ·  " + clock(now, zone),
                     size: 24, colour: Ink.blue, tracking: 0.2)
            }
            .padding(.bottom, 22 * u)
            BridgeRule(toward: wing, bleed: 64 + 14)
        }
    }
}

// MARK: - The strip

/// The next day as a strip, an hour back to twenty-three ahead: the temperature as a trace
/// over it with the chance of rain under that, the daylight as a band with the hours beneath,
/// and the calendar's timed events as panels in two lanes, the one under way lit. A gold
/// line stands at now.
private struct Strip: View {
    let snapshot: Snapshot
    let now: Date
    /// In layout points.
    let width: CGFloat
    @Environment(\.stewardUnit) private var u

    private static let lanes = 2
    private static let laneHeight: CGFloat = 70
    private static let laneGap: CGFloat = 10
    private static let traceHeight: CGFloat = 112
    private static let bandHeight: CGFloat = 18
    /// Room for an event's name at least, so a short one keeps the next clear of it.
    private static let minLabel: CGFloat = 210

    var body: some View {
        let window = Steward.Window(now: now)
        let zone = snapshot.timeZone
        let sunTimes = Skylight.sunTimes(snapshot, now: now)
        let rise = sunTimes.first { $0.rise && $0.time > now }?.time
        let set = sunTimes.first { !$0.rise && $0.time > now }?.time
        var detail = ["Next 24 h"]
        if let rise { detail.append("rise " + clock(rise, zone)) }
        if let set { detail.append("set " + clock(set, zone)) }
        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title: "The day ahead", detail: detail.joined(separator: " · "))
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    trace(window)
                        .frame(height: Self.traceHeight * u)
                    band(window, sunTimes: sunTimes, zone: zone)
                        .frame(height: Self.bandHeight * u)
                    hours(window, zone: zone)
                        .frame(height: 34 * u)
                    events(window, zone: zone)
                        .padding(.top, 10 * u)
                }
                nowLine(window)
            }
            .padding(.top, 14 * u)
        }
    }

    private func x(_ fraction: Double) -> CGFloat { CGFloat(fraction) * width * u }

    /// The temperature through the day, as a line with its readings, and the chance of rain as
    /// bars under it.
    @ViewBuilder private func trace(_ window: Steward.Window) -> some View {
        if let weather = snapshot.sources.weather?.data {
            let points = Steward.trace(weather, now: now, window: window)
            let lo = points.map(\.temp).min() ?? 0, hi = points.map(\.temp).max() ?? 1
            let top = 38 * u, bottom = (Self.traceHeight - 16) * u
            let y = { (t: Double) in bottom - CGFloat(Cyberpunk.fraction(t, low: lo, high: hi)) * (bottom - top) }
            ZStack(alignment: .topLeading) {
                Canvas { gc, size in
                    for p in points where p.precipChance > 0.05 {
                        let h = CGFloat(p.precipChance) * 44 * u
                        let px = x(window.fraction(p.time))
                        gc.fill(Path(CGRect(x: px - 9 * u, y: size.height - h, width: 18 * u, height: h)),
                                with: .color(Ink.blue.opacity(0.16)))
                    }
                    var line = Path()
                    for (i, p) in points.enumerated() {
                        let at = CGPoint(x: x(window.fraction(p.time)), y: y(p.temp))
                        i == 0 ? line.move(to: at) : line.addLine(to: at)
                    }
                    gc.stroke(line, with: .color(Ink.blue.opacity(0.75)), lineWidth: 2 * u)
                    for p in points {
                        let at = CGPoint(x: x(window.fraction(p.time)), y: y(p.temp))
                        let s = 7 * u
                        gc.fill(Path(CGRect(x: at.x - s / 2, y: at.y - s / 2, width: s, height: s)),
                                with: .color(p.isNow ? Ink.goldHot : Ink.blue))
                    }
                }
                ForEach(points, id: \.time) { p in
                    Caps(text: degrees(p.temp), size: 18, weight: 600,
                         colour: p.isNow ? Ink.goldHot : Ink.white.opacity(0.85), tracking: 0.04)
                        .fixedSize()
                        .position(x: x(window.fraction(p.time)), y: y(p.temp) - 20 * u)
                }
            }
        } else {
            Color.clear
        }
    }

    /// The daylight as a lit band along a hairline, and a tick each hour.
    private func band(_ window: Steward.Window, sunTimes: [(time: Date, rise: Bool)], zone: TimeZone) -> some View {
        let stretches = Steward.daylight(sunTimes, window: window)
        let ticks = Steward.hours(in: window, zone: zone)
        return Canvas { gc, size in
            let mid = size.height / 2
            gc.fill(Path(CGRect(x: 0, y: mid - 0.6 * u, width: size.width, height: 1.2 * u)), with: .color(.white.opacity(0.14)))
            for s in stretches {
                let r = CGRect(x: x(s.lowerBound), y: mid - 4 * u, width: x(s.upperBound) - x(s.lowerBound), height: 8 * u)
                gc.fill(Path(r), with: .linearGradient(Gradient(colors: [Ink.blue.opacity(0.18), Ink.blue.opacity(0.38), Ink.blue.opacity(0.18)]),
                                                       startPoint: CGPoint(x: r.minX, y: 0), endPoint: CGPoint(x: r.maxX, y: 0)))
            }
            for tick in ticks {
                let tx = x(window.fraction(tick))
                gc.fill(Path(CGRect(x: tx - 0.6 * u, y: mid + 5 * u, width: 1.2 * u, height: 5 * u)), with: .color(Ink.dim))
            }
        }
    }

    /// The hours under the band, as many as fit.
    private func hours(_ window: Steward.Window, zone: TimeZone) -> some View {
        let hourWidth = Double(width) / window.hours
        let step = Steward.labelStep(hourWidth: hourWidth, minSpacing: 92)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        // Clear of now's label, and of the ends.
        let labels = Steward.hours(in: window, zone: zone).filter { tick in
            let f = window.fraction(tick)
            return cal.component(.hour, from: tick) % step == 0 && abs(f - window.fraction(now)) > 0.025 && f > 0.015 && f < 0.985
        }
        return ZStack(alignment: .topLeading) {
            ForEach(labels, id: \.self) { t in
                Caps(text: hour(t, zone), size: 15, weight: 500, colour: Ink.muted, tracking: 0.14)
                    .fixedSize()
                    .position(x: x(window.fraction(t)), y: 17 * u)
            }
        }
    }

    /// The timed events in their lanes.
    private func events(_ window: Steward.Window, zone: TimeZone) -> some View {
        let spans = Steward.spans(snapshot, now: now, window: window)
        let lanes = Steward.lanes(spans.map { ($0.start, $0.end) }, minLength: Double(Self.minLabel / width), count: Self.lanes)
        let placed = zip(spans, lanes).compactMap { span, lane in lane.map { (span, $0) } }
        return ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(placed, id: \.0) { span, lane in
                let w = max(x(span.end) - x(span.start), Self.minLabel * u - 8 * u)
                EventPanel(span: span, zone: zone)
                    .frame(width: w, height: Self.laneHeight * u)
                    .offset(x: x(span.start), y: CGFloat(lane) * (Self.laneHeight + Self.laneGap) * u)
            }
        }
        .frame(height: (CGFloat(Self.lanes) * Self.laneHeight + CGFloat(Self.lanes - 1) * Self.laneGap) * u, alignment: .topLeading)
    }

    /// A gold line at now, from the trace to the last lane, with its label.
    private func nowLine(_ window: Steward.Window) -> some View {
        let at = x(window.fraction(now))
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(Ink.gold)
                .frame(width: 2 * u)
                .shadow(color: Ink.gold.opacity(0.8), radius: 6 * u)
                .padding(.top, 8 * u)
                .offset(x: at - u)
            Caps(text: "Now", size: 15, weight: 700, colour: Ink.goldHot, tracking: 0.2)
                .fixedSize()
                .position(x: at, y: (Self.traceHeight + Self.bandHeight + 17) * u)
                .background(alignment: .topLeading) {
                    Rectangle().fill(Ink.deep)
                        .frame(width: 52 * u, height: 22 * u)
                        .position(x: at, y: (Self.traceHeight + Self.bandHeight + 17) * u)
                }
        }
        .allowsHitTesting(false)
    }
}

/// An event on the strip: its name and when, in a panel lit while it is under way.
private struct EventPanel: View {
    let span: Steward.Span
    let zone: TimeZone
    @Environment(\.stewardUnit) private var u

    var body: some View {
        let tone: Panel.Tone = switch span.state {
        case .active: .lit
        case .next: .next
        default: .quiet
        }
        var detail = clock(span.event.start, zone)
        if let place = span.event.shortLocation { detail += " · " + place }
        return VStack(alignment: .leading, spacing: 3 * u) {
            Text(span.event.summary)
                .font(Face.cond(24 * u, 600))
                .foregroundStyle(span.state == .past ? Ink.muted : Ink.white)
                .lineLimit(1)
            Caps(text: detail, size: 13, weight: 600,
                 colour: span.state == .active ? Ink.goldHot : span.state == .next ? Ink.blue : Ink.muted, tracking: 0.14)
        }
        .padding(.leading, 16 * u)
        .padding(.trailing, 10 * u)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Panel(tone: tone, cut: 12))
        .opacity(span.state == .past ? 0.55 : 1)
    }
}

// MARK: - The agenda

/// Seneschal's rows, one panel each: what is on now lit, the next in blue, then the rest of
/// today and tomorrow, and birthdays in the fortnight after.
private struct AgendaColumn: View {
    let snapshot: Snapshot
    let now: Date
    @Environment(\.stewardUnit) private var u

    private static let rows = 6

    var body: some View {
        let zone = snapshot.timeZone
        let contacts = Cyberpunk.contacts(snapshot, now: now, limit: 2)
        let jobs = Cyberpunk.jobs(snapshot, now: now, limit: Self.rows - min(contacts.count, 1))
        let room = Self.rows - jobs.count
        let active = jobs.filter { $0.state == .active }.count
        VStack(alignment: .leading, spacing: 10 * u) {
            SectionLabel(title: active > 0 ? "On now · \(active)" : "Agenda",
                         detail: jobs.isEmpty ? nil : "\(jobs.count) ahead")
            if jobs.isEmpty && contacts.isEmpty {
                row(symbol: "calendar", title: "Nothing ahead", detail: "Today and tomorrow are clear", tone: .quiet)
            }
            ForEach(jobs, id: \.self) { job in
                let tone: Panel.Tone = job.state == .active ? .lit : job.state == .tracked ? .next : .quiet
                row(symbol: job.state == .allDay ? "sun.max" : "calendar", title: job.event.summary,
                    detail: when(job, zone: zone), tone: tone)
            }
            ForEach(contacts.prefix(room), id: \.self) { birthday in
                let day = CivilDate(now, in: zone) == birthday.date ? "Today"
                    : birthday.date.start(in: zone).formatted(Date.FormatStyle(timeZone: zone).weekday(.wide))
                row(symbol: "gift", title: birthday.name,
                    detail: day + (birthday.age.map { " · turns \($0)" } ?? ""), tone: .quiet)
            }
        }
    }

    private func when(_ job: Cyberpunk.Job, zone: TimeZone) -> String {
        switch job.state {
        case .allDay: "All day"
        case .active: "Until " + clock(job.event.end, zone)
        default: Skylight.when(job.event, now: now, zone: zone)
        }
    }

    private func row(symbol: String, title: String, detail: String, tone: Panel.Tone) -> some View {
        let lit = tone == .lit
        return HStack(spacing: 18 * u) {
            Image(systemName: symbol)
                .font(.system(size: 22 * u, weight: .regular))
                .foregroundStyle(lit ? Ink.goldHot : tone == .next ? Ink.blue : Ink.white.opacity(0.6))
                .frame(width: 30 * u)
            Text(title)
                .font(Face.cond(27 * u, 500))
                .foregroundStyle(Ink.white)
                .lineLimit(1)
            Spacer(minLength: 12 * u)
            Caps(text: detail, size: 15, weight: 600, colour: lit ? Ink.goldHot : tone == .next ? Ink.blue : Ink.muted, tracking: 0.14)
                .fixedSize()
        }
        .padding(.leading, 20 * u)
        .padding(.trailing, 24 * u)
        .frame(height: 58 * u)
        .background(Panel(tone: tone))
    }
}

// MARK: - The conditions

/// The weather now: the sky and the temperature, any alert as a red panel, and the readings
/// as a grid of slabs.
private struct Conditions: View {
    let snapshot: Snapshot
    let now: Date
    @Environment(\.stewardUnit) private var u

    var body: some View {
        let zone = snapshot.timeZone
        VStack(alignment: .leading, spacing: 10 * u) {
            SectionLabel(title: "Conditions",
                         detail: snapshot.sources.weather?.data?.locationName ?? snapshot.sources.weather?.fetchedAt.map { "checked " + clock($0, zone) })
            if let weather = snapshot.sources.weather?.data {
                HStack(alignment: .center, spacing: 22 * u) {
                    Image(systemName: WeatherSymbol.name(for: weather.currentIcon))
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 62 * u, weight: .light))
                        .foregroundStyle(Ink.white.opacity(0.9))
                        .frame(width: 84 * u)
                    // Michroma's degree sign is a full-size ring; Saira's sits as one should.
                    (Text("\(Int(weather.currentTemp.rounded()))").font(Face.wide(70 * u))
                        + Text("°").font(Face.cond(70 * u, 400)))
                        .foregroundStyle(Ink.white)
                        .fixedSize()
                    VStack(alignment: .leading, spacing: 4 * u) {
                        Caps(text: weather.currentDescription, size: 22, colour: Ink.white.opacity(0.9), tracking: 0.12)
                        Caps(text: "H \(degrees(weather.high))  L \(degrees(weather.low))"
                             + (weather.feelsLike.map { "  feels \(degrees($0))" } ?? ""),
                             size: 17, weight: 500, colour: Ink.blue, tracking: 0.14)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 104 * u)
                if let alert = weather.alerts.first {
                    HStack(spacing: 12 * u) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 20 * u, weight: .medium))
                        Caps(text: alert.event, size: 18, weight: 700, colour: Ink.red, tracking: 0.16)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Ink.red)
                    .padding(.horizontal, 20 * u)
                    .frame(height: 46 * u)
                    .background(Panel(tone: .urgent, cut: 10))
                }
                let cells = readings(weather, zone: zone)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10 * u), count: 3), spacing: 10 * u) {
                    ForEach(cells.prefix(6), id: \.label) { cell in
                        VStack(alignment: .leading, spacing: 4 * u) {
                            Caps(text: cell.label, size: 13, weight: 600, colour: Ink.muted, tracking: 0.18)
                            Text(cell.value)
                                .font(Face.cond(29 * u, 600))
                                .foregroundStyle(cell.urgent ? Ink.red : Ink.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .padding(.horizontal, 16 * u)
                        .frame(maxWidth: .infinity, minHeight: 80 * u, alignment: .leading)
                        .background(Panel(tone: cell.urgent ? .urgent : .quiet, cut: 10))
                    }
                }
            } else {
                Caps(text: "No weather from the Pi", size: 20, colour: Ink.muted)
                    .frame(maxWidth: .infinity, minHeight: 200 * u)
            }
        }
    }

    private struct Cell {
        let label: String
        let value: String
        var urgent = false
    }

    private func readings(_ w: Weather, zone: TimeZone) -> [Cell] {
        var cells = [Cell(label: "Humidity", value: "\(w.humidity)%")]
        if let s = w.windSpeed {
            cells.append(Cell(label: "Wind", value: "\(Int(s.rounded())) \(w.windDeg.map { Compass.point($0) } ?? "") \(snapshot.isMetric ? "m/s" : "mph")"))
        }
        if let air = snapshot.sources.airQuality?.data {
            cells.append(Cell(label: "Air · " + air.shortLabel, value: "\(air.aqi) AQI", urgent: air.band >= .unhealthy))
        }
        if let uv = w.uvIndex {
            cells.append(Cell(label: "UV · " + Weatherglass.uvCategory(uv), value: "\(Int(uv.rounded()))"))
        }
        if let p = w.pressure { cells.append(Cell(label: "Pressure", value: "\(Int(p.rounded())) hPa")) }
        if let moon = snapshot.moon {
            cells.append(Cell(label: moon.phaseName, value: "\(Int((moon.today?.illumination ?? 0).rounded()))% lit"))
        }
        return cells
    }
}

// MARK: - The outlook

/// The days ahead as tall slabs, today first, as many as the width holds: on a wide display,
/// the week.
private struct Outlook: View {
    let snapshot: Snapshot
    let now: Date
    /// In layout points.
    let width: CGFloat
    @Environment(\.stewardUnit) private var u

    private static let gap: CGFloat = 10
    private static let minCell: CGFloat = 150

    var body: some View {
        let zone = snapshot.timeZone
        let fits = max(1, Int((width + Self.gap) / (Self.minCell + Self.gap)))
        let days = snapshot.sources.weather?.data.map { Skylight.outlook($0, now: now, zone: zone, count: min(fits, 7)) } ?? []
        let today = CivilDate(now, in: zone)
        VStack(alignment: .leading, spacing: 10 * u) {
            SectionLabel(title: "Outlook", detail: days.isEmpty ? nil : "\(days.count) days")
            HStack(spacing: Self.gap * u) {
                ForEach(days, id: \.self) { day in
                    VStack(spacing: 18 * u) {
                        Caps(text: day.date == today ? "Today"
                             : day.date.start(in: zone).formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated)),
                             size: 17, colour: day.date == today ? Ink.blue : Ink.white.opacity(0.72))
                        Image(systemName: WeatherSymbol.name(for: day.icon))
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 58 * u, weight: .light))
                            .foregroundStyle(Ink.white.opacity(0.88))
                            .frame(height: 96 * u)
                        HStack(alignment: .firstTextBaseline, spacing: 10 * u) {
                            Text(degrees(day.high)).font(Face.cond(42 * u, 600)).foregroundStyle(Ink.white)
                            Text(degrees(day.low)).font(Face.cond(30 * u, 500)).foregroundStyle(Ink.muted)
                        }
                        .fixedSize()
                        Caps(text: (day.precipChance ?? 0) >= 0.2 ? "\(Int(((day.precipChance ?? 0) * 100).rounded()))% rain" : "Dry",
                             size: 14, weight: 600, colour: (day.precipChance ?? 0) >= 0.2 ? Ink.blue : Ink.muted, tracking: 0.16)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 330 * u)
                    .background(Panel(tone: .quiet))
                    .overlay(alignment: .top) {
                        if day.date == today { Rectangle().fill(Ink.blue.opacity(0.8)).frame(height: 2.5 * u) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - The dispatch

/// The day's quote along the foot, as Seneschal sets its notes: reading text, quietly.
private struct Dispatch: View {
    let quote: Quote?
    @Environment(\.stewardUnit) private var u

    var body: some View {
        if let quote {
            HStack(alignment: .firstTextBaseline, spacing: 16 * u) {
                Rectangle().fill(Ink.muted.opacity(0.7)).frame(width: 18 * u, height: 2.5 * u)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 7 * u }
                Text("“\(quote.text)”")
                    .font(Face.text(22 * u, 300))
                    .foregroundStyle(Ink.white.opacity(0.62))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Caps(text: quote.author, size: 15, colour: Ink.muted, tracking: 0.2)
                    .fixedSize()
            }
        }
    }
}

// MARK: - The wing

/// The wing's header: its name small, at the outer edge, over the bridge rule, whose gold
/// runs off the inner edge to meet the main display's.
private struct WingHeader: View {
    let snapshot: Snapshot
    let inner: HorizontalEdge
    @Environment(\.stewardUnit) private var u

    var body: some View {
        let stale = Steward.stale(snapshot.sources)
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: 14 * u) {
                Rectangle().fill(Ink.muted.opacity(0.7)).frame(width: 18 * u, height: 2.5 * u)
                Caps(text: "Steward · Now", size: 18, colour: Ink.white.opacity(0.6), tracking: 0.3)
                if !stale.isEmpty {
                    Caps(text: stale.joined(separator: ", ") + " stale", size: 16, colour: Ink.red, tracking: 0.18)
                }
            }
            .environment(\.layoutDirection, inner == .trailing ? .leftToRight : .rightToLeft)
            .frame(maxWidth: .infinity, alignment: inner == .trailing ? .leading : .trailing)
            .padding(.bottom, 22 * u)
            BridgeRule(toward: inner, run: 420, bleed: 96 + 14)
        }
    }
}

/// What is on now, or next: one panel, lit while it is under way.
private struct NextUp: View {
    let snapshot: Snapshot
    let now: Date
    let align: HorizontalAlignment
    @Environment(\.stewardUnit) private var u

    var body: some View {
        let zone = snapshot.timeZone
        let job = Cyberpunk.jobs(snapshot, now: now, limit: 4).first { $0.state == .active || $0.state == .tracked }
        let birthday = Cyberpunk.contacts(snapshot, now: now, limit: 1).first { $0.date == CivilDate(now, in: zone) }
        VStack(alignment: .leading, spacing: 12 * u) {
            SectionLabel(title: job?.state == .active ? "On now" : "Next")
            if let job {
                panel(title: job.event.summary, detail: detail(job, zone: zone), symbol: "calendar",
                      tone: job.state == .active ? .lit : .next)
            } else {
                panel(title: "Nothing ahead", detail: "Today and tomorrow are clear", symbol: "calendar", tone: .quiet)
            }
            if let birthday {
                panel(title: birthday.name, detail: "Birthday today" + (birthday.age.map { " · turns \($0)" } ?? ""),
                      symbol: "gift", tone: .quiet)
            }
        }
    }

    private func detail(_ job: Cyberpunk.Job, zone: TimeZone) -> String {
        var detail = job.state == .active ? "Until " + clock(job.event.end, zone) : Skylight.when(job.event, now: now, zone: zone)
        if let place = job.event.shortLocation { detail += " · " + place }
        return detail
    }

    private func panel(title: String, detail: String, symbol: String, tone: Panel.Tone) -> some View {
        let lit = tone == .lit
        return HStack(spacing: 24 * u) {
            Image(systemName: symbol)
                .font(.system(size: 34 * u, weight: .regular))
                .foregroundStyle(lit ? Ink.goldHot : tone == .next ? Ink.blue : Ink.white.opacity(0.6))
                .frame(width: 44 * u)
            VStack(alignment: .leading, spacing: 6 * u) {
                Text(title)
                    .font(Face.cond(44 * u, 500))
                    .foregroundStyle(Ink.white)
                    .lineLimit(1)
                Caps(text: detail, size: 19, weight: 600, colour: lit ? Ink.goldHot : tone == .next ? Ink.blue : Ink.muted, tracking: 0.16)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 30 * u)
        .padding(.trailing, 24 * u)
        .frame(height: 124 * u)
        .background(Panel(tone: tone, cut: 18))
    }
}

/// The sky as three quiet marks along the foot, Night's in Seneschal's dress: the moon, the
/// temperature with the sky's glyph, and the air. A mark without data is left out.
private struct Marks: View {
    let snapshot: Snapshot
    let inner: HorizontalEdge
    @Environment(\.stewardUnit) private var u

    var body: some View {
        let weather = snapshot.sources.weather?.data
        HStack(alignment: .bottom, spacing: 72 * u) {
            if let moon = snapshot.moon, let today = moon.today {
                mark(label: moon.phaseName) {
                    MoonDisc(fraction: today.fraction, radius: 34 * u)
                        .frame(width: 68 * u, height: 68 * u)
                }
            }
            if let weather {
                mark(label: weather.currentDescription) {
                    HStack(alignment: .center, spacing: 18 * u) {
                        Image(systemName: WeatherSymbol.name(for: weather.currentIcon))
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 50 * u, weight: .light))
                            .foregroundStyle(Ink.white.opacity(0.8))
                        (Text("\(Int(weather.currentTemp.rounded()))").font(Face.wide(54 * u))
                            + Text("°").font(Face.cond(54 * u, 400)))
                            .foregroundStyle(Ink.white.opacity(0.9))
                    }
                }
            }
            if let air = snapshot.sources.airQuality?.data {
                mark(label: "Air · " + air.shortLabel) {
                    Text("\(air.aqi)")
                        .font(Face.wide(54 * u))
                        .foregroundStyle(air.band >= .unhealthy ? Ink.red : Ink.white.opacity(0.9))
                }
            }
        }
        .fixedSize()
        // The marks read outward from the inner edge, the moon farthest from it.
        .environment(\.layoutDirection, inner == .trailing ? .leftToRight : .rightToLeft)
    }

    private func mark<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 14 * u) {
            content()
                .frame(height: 72 * u)
                .environment(\.layoutDirection, .leftToRight)
            Caps(text: label, size: 15, weight: 600, colour: Ink.muted, tracking: 0.24)
        }
    }
}
