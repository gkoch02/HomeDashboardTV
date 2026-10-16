import DashboardCore
import SwiftUI

/// The Pi's `light_cycle` theme: today as one 24-hour dial, midnight at the top, with the
/// numbers beside it.
///
/// The dial's band is the sky through the day, coloured by the sun's altitude as Horizon
/// colours its sky, with stars where it is darkest and a rule across it at sunrise and
/// sunset. Today's timed events ride inside it as arcs over their hours (in progress red,
/// still to come ochre, ended hollow), and the sun, or the moon at tonight's phase after
/// dark, rides the band at the current minute on a needle from the date at the centre. The
/// column carries sunrise, sunset and the day's length, how much shorter or longer tomorrow
/// is (from the Pi's `sun` block, so only with coordinates), the weather now and the day's
/// agenda.
struct LightCycleView: Theme {
    let snapshot: Snapshot
    let now: Date

    private var zone: TimeZone { snapshot.timeZone }
    private var today: CivilDate { CivilDate(now, in: zone) }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let dial = min(size.height, size.width * 0.52)
            HStack(alignment: .center, spacing: size.width * 0.05) {
                Dial(snapshot: snapshot, now: now, day: today)
                    .frame(width: dial, height: dial)
                Column(snapshot: snapshot, now: now, day: today, height: size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(width: size.width, height: size.height)
        }
        .padding(.vertical, 10)
    }

    var backdrop: some View { Ink.plate }
}

private enum Ink {
    static let plate = Color(red: 0.075, green: 0.078, blue: 0.094)
    static let disc = Color(red: 0.105, green: 0.108, blue: 0.128)
    static let cream = Color(red: 0.95, green: 0.93, blue: 0.88)
    static let faint = cream.opacity(0.55)
    static let rule = cream.opacity(0.22)
    static let red = Color(red: 0.93, green: 0.36, blue: 0.30)
    static let yellow = Color(red: 0.98, green: 0.80, blue: 0.33)
}

private enum Face {
    static let sans = "DMSans-9ptRegular"
    static let numeral = "Righteous-Regular"
}

// MARK: - The dial

/// Proportions of the rim's radius, after the panel's (`_OUTER_R` 196 px).
private enum Ring {
    static let label = 1.11
    static let rim = 1.0
    static let bandOuter = 0.885
    static let bandInner = 0.70
    static let laneOuter = 0.665
    static let laneWidth = 0.05
    static let laneGap = 0.014
    static let disc = 0.52
    static let halo = 0.085
}

private struct Dial: View {
    let snapshot: Snapshot
    let now: Date
    let day: CivilDate

    private var zone: TimeZone { snapshot.timeZone }

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let r = side / 2 / 1.17
            let centre = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let sun = SunModel(snapshot: snapshot)
            let nowHour = LightCycle.hour(now, in: zone)
            ZStack {
                Band(altitudes: LightCycle.altitudes(sun, on: day), horizons: horizons(sun), r: r)
                    .equatable()
                Canvas { context, _ in
                    ticks(&context, centre: centre, r: r)
                    events(&context, centre: centre, r: r, nowHour: nowHour)
                    needle(&context, centre: centre, r: r, hour: nowHour)
                }
                labels(centre: centre, r: r)
                CentreDisc(day: day, zone: zone, r: r)
                    .position(centre)
                glyph(r: r, isDay: sun.altitude(at: now) > -0.833)
                    .position(polar(centre, (Ring.bandOuter + Ring.bandInner) / 2 * r, nowHour))
            }
        }
    }

    private func horizons(_ sun: SunModel) -> [Double] {
        guard let times = LightCycle.daylight(snapshot, sun: sun, on: day) else { return [] }
        return [LightCycle.hour(times.rise, in: zone), LightCycle.hour(times.set, in: zone)]
    }

    private func ticks(_ context: inout GraphicsContext, centre: CGPoint, r: CGFloat) {
        context.stroke(Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r)),
                       with: .color(Ink.cream), lineWidth: 3)
        for quarter in 0..<96 {
            let hour = Double(quarter) / 4
            let (inner, width, ink): (Double, CGFloat, Color) =
                quarter % 24 == 0 ? (0.90, 4, Ink.cream)
                : quarter % 4 == 0 ? (0.945, 2.5, Ink.cream)
                : (0.975, 1.5, Ink.faint)
            var tick = Path()
            tick.move(to: polar(centre, inner * r, hour))
            tick.addLine(to: polar(centre, r, hour))
            context.stroke(tick, with: .color(ink), lineWidth: width)
        }
    }

    /// Each timed event as an arc over its hours: red while it runs, ochre to come, an
    /// outline once it has ended.
    private func events(_ context: inout GraphicsContext, centre: CGPoint, r: CGFloat, nowHour: Double) {
        let events = snapshot.sources.events?.data ?? []
        for span in LightCycle.spans(events, on: day, zone: zone) {
            let outer = (Ring.laneOuter - Double(span.lane) * (Ring.laneWidth + Ring.laneGap)) * r
            let path = sector(centre, inner: outer - Ring.laneWidth * r, outer: outer, from: span.start, to: span.end)
            if span.end <= nowHour {
                context.stroke(path, with: .color(Ink.faint), lineWidth: 2)
            } else {
                context.fill(path, with: .color(span.start <= nowHour ? Ink.red : Ink.yellow))
            }
        }
    }

    private func needle(_ context: inout GraphicsContext, centre: CGPoint, r: CGFloat, hour: Double) {
        let base = Ring.disc * r + 2
        let tip = ((Ring.bandOuter + Ring.bandInner) / 2 - Ring.halo) * r - 4
        let half = 0.025 * r
        let a = angle(hour)
        let across = CGPoint(x: -sin(a) * half, y: cos(a) * half)
        let root = polar(centre, base, hour)
        var path = Path()
        path.move(to: CGPoint(x: root.x + across.x, y: root.y + across.y))
        path.addLine(to: polar(centre, tip, hour))
        path.addLine(to: CGPoint(x: root.x - across.x, y: root.y - across.y))
        path.closeSubpath()
        context.fill(path, with: .color(Ink.cream))
    }

    private func labels(centre: CGPoint, r: CGFloat) -> some View {
        ForEach(0..<8, id: \.self) { i in
            let hour = i * 3
            let major = hour % 6 == 0
            Text(String(format: "%02d", hour))
                .font(.custom(Face.sans, size: (major ? 0.085 : 0.06) * r).weight(major ? .bold : .semibold))
                .foregroundStyle(major ? Ink.cream : Ink.faint)
                .position(polar(centre, Ring.label * r, Double(hour)))
        }
    }

    /// The sun by day; after dark the moon at tonight's phase, or a plain disc without it.
    @ViewBuilder private func glyph(r: CGFloat, isDay: Bool) -> some View {
        let radius = Ring.halo * r
        if isDay {
            SunGlyph(radius: radius)
        } else {
            ZStack {
                Circle().fill(Ink.plate)
                Circle().stroke(Ink.cream.opacity(0.7), lineWidth: 2)
                if let fraction = snapshot.moon?.today?.fraction {
                    MoonDisc(fraction: fraction, radius: radius * 0.8)
                } else {
                    Circle().fill(Ink.cream).padding(radius * 0.35)
                }
            }
            .frame(width: radius * 2, height: radius * 2)
        }
    }
}

/// The sky band: today's altitudes as a conic gradient, stars in the darkest stretch, and a
/// rule across it at sunrise and sunset. Equatable, so the minute ticks never repaint it.
private struct Band: View, Equatable {
    let altitudes: [Double]
    let horizons: [Double]
    let r: CGFloat

    var body: some View {
        Canvas { context, size in
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let ring = sector(centre, inner: Ring.bandInner * r, outer: Ring.bandOuter * r, from: 0, to: 24)
            let n = altitudes.count - 1
            let stops = altitudes.enumerated().map { i, alt in
                Gradient.Stop(color: SkyColour.color(alt), location: Double(i) / Double(n))
            }
            context.fill(ring, with: .conicGradient(Gradient(stops: stops), center: centre, angle: .degrees(-90)))

            var random = SplitMix(seed: 0x4C69_6768)
            for i in 0..<n * 3 {
                let hour = (Double(i) + random.unit()) / Double(n * 3) * 24
                let radius = (Ring.bandInner + 0.02 + random.unit() * (Ring.bandOuter - Ring.bandInner - 0.04)) * r
                let alt = altitudes[min(n, Int(hour / 24 * Double(n)))]
                let dot = 0.6 + pow(random.unit(), 3) * 2.4
                let alpha = 0.3 + random.unit() * 0.6
                guard alt < -14 else { continue }
                let p = polar(centre, radius, hour)
                context.fill(Path(ellipseIn: CGRect(x: p.x - dot, y: p.y - dot, width: 2 * dot, height: 2 * dot)),
                             with: .color(.white.opacity(alpha * min(1, (-14 - alt) / 4))))
            }

            for edge in [Ring.bandInner, Ring.bandOuter] {
                let e = edge * r
                context.stroke(Path(ellipseIn: CGRect(x: centre.x - e, y: centre.y - e, width: 2 * e, height: 2 * e)),
                               with: .color(Ink.cream.opacity(0.6)), lineWidth: 1.5)
            }
            for hour in horizons {
                var rule = Path()
                rule.move(to: polar(centre, (Ring.bandInner - 0.02) * r, hour))
                rule.addLine(to: polar(centre, (Ring.bandOuter + 0.02) * r, hour))
                context.stroke(rule, with: .color(Ink.cream), lineWidth: 4)
            }
        }
    }
}

private struct CentreDisc: View {
    let day: CivilDate
    let zone: TimeZone
    let r: CGFloat

    var body: some View {
        let date = day.start(in: zone)
        ZStack {
            Circle().fill(Ink.disc)
            Circle().stroke(Ink.cream, lineWidth: 3)
            Circle().stroke(Ink.cream.opacity(0.4), lineWidth: 1.5).padding(0.035 * r)
            VStack(spacing: 0.02 * r) {
                Text(date.formatted(Date.FormatStyle(timeZone: zone).weekday(.wide)).uppercased())
                    .font(.custom(Face.sans, size: 0.075 * r).weight(.bold))
                    .tracking(0.012 * r)
                Text("\(day.day)")
                    .font(.custom(Face.numeral, size: 0.42 * r))
                    .padding(.vertical, -0.06 * r)
                Text(date.formatted(Date.FormatStyle(timeZone: zone).month(.wide)).uppercased())
                    .font(.custom(Face.sans, size: 0.075 * r).weight(.bold))
                    .tracking(0.012 * r)
                    .foregroundStyle(Ink.yellow)
            }
            .foregroundStyle(Ink.cream)
        }
        .frame(width: 2 * Ring.disc * r, height: 2 * Ring.disc * r)
    }
}

/// A small glowing sun, lit from the upper left as Horizon draws its noons.
private struct SunGlyph: View {
    let radius: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.85, blue: 0.55).opacity(0.5), .clear],
                                     center: .center, startRadius: radius * 0.8, endRadius: radius * 2.2))
                .frame(width: radius * 4.4, height: radius * 4.4)
            Circle()
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.98, blue: 0.88), Color(red: 1, green: 0.86, blue: 0.50),
                                              Color(red: 0.97, green: 0.66, blue: 0.24)],
                                     center: UnitPoint(x: 0.38, y: 0.38), startRadius: 0, endRadius: radius * 1.2))
                .frame(width: radius * 2, height: radius * 2)
        }
    }
}

// MARK: Dial geometry

/// Clockwise from midnight at the top, in screen coordinates (y down).
private func angle(_ hour: Double) -> Double { (hour / 24 * 360 - 90) * .pi / 180 }

private func polar(_ centre: CGPoint, _ radius: CGFloat, _ hour: Double) -> CGPoint {
    CGPoint(x: centre.x + radius * cos(angle(hour)), y: centre.y + radius * sin(angle(hour)))
}

/// The ring between two radii from one hour to another.
private func sector(_ centre: CGPoint, inner: CGFloat, outer: CGFloat, from: Double, to: Double) -> Path {
    var path = Path()
    path.addArc(center: centre, radius: outer, startAngle: .radians(angle(from)), endAngle: .radians(angle(to)), clockwise: false)
    path.addArc(center: centre, radius: inner, startAngle: .radians(angle(to)), endAngle: .radians(angle(from)), clockwise: true)
    path.closeSubpath()
    return path
}

// MARK: - The column

private struct Column: View {
    let snapshot: Snapshot
    let now: Date
    let day: CivilDate
    let height: CGFloat

    private var zone: TimeZone { snapshot.timeZone }
    private var weather: Weather? { snapshot.sources.weather?.data }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading
            rule.padding(.top, 16)
            sunRow.padding(.top, 26)
            if let weather {
                rule.padding(.top, 26)
                reading(weather).padding(.top, 26)
            }
            rule.padding(.top, 26)
            agenda.padding(.top, 24)
            Spacer(minLength: 16)
            foot
        }
        .foregroundStyle(Ink.cream)
        .padding(.vertical, 24)
    }

    private var rule: some View { Rectangle().fill(Ink.cream.opacity(0.4)).frame(height: 1.5) }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.custom(Face.sans, size: 20).weight(.bold))
            .tracking(2)
            .foregroundStyle(Ink.yellow)
            .lineLimit(1)
    }

    private var heading: some View {
        let place = weather?.locationName.map { " · \($0.uppercased())" } ?? ""
        return Text("LIGHT CYCLE\(place)")
            .font(.custom(Face.sans, size: 26).weight(.heavy))
            .tracking(2.5)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var sunRow: some View {
        let sun = SunModel(snapshot: snapshot)
        let times = LightCycle.daylight(snapshot, sun: sun, on: day)
        let change = LightCycle.dayLengthChange(sun, from: day)
        return VStack(alignment: .trailing, spacing: 6) {
            HStack(alignment: .top, spacing: 0) {
                cell("SUNRISE", times.map { CompactTime.string($0.rise, in: zone) } ?? "—")
                cell("SUNSET", times.map { CompactTime.string($0.set, in: zone) } ?? "—")
                cell("DAYLIGHT", times.map { LightCycle.formatLength($0.set.timeIntervalSince($0.rise)) } ?? "—")
            }
            if let change {
                Text("\(LightCycle.formatChange(change)) tomorrow")
                    .font(.custom(Face.sans, size: 21).weight(.semibold))
                    .foregroundStyle(Ink.faint)
            }
        }
    }

    private func cell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            label(title)
            Text(value)
                .font(.custom(Face.sans, size: 46).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reading(_ w: Weather) -> some View {
        HStack(alignment: .center, spacing: 24) {
            Image(systemName: WeatherSymbol.name(for: w.currentIcon))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 64))
                .frame(width: 92)
            Text("\(Int(w.currentTemp.rounded()))°")
                .font(.custom(Face.sans, size: 84).weight(.bold))
                .lineLimit(1)
            VStack(alignment: .leading, spacing: 4) {
                Text(w.currentDescription.capitalized)
                    .font(.custom(Face.sans, size: 30).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("H \(Int(w.high.rounded()))°   L \(Int(w.low.rounded()))°")
                    .font(.custom(Face.sans, size: 26).weight(.medium))
                    .foregroundStyle(Ink.cream.opacity(0.85))
            }
        }
    }

    // MARK: Agenda

    private var agenda: some View {
        let events = Agenda.days(from: snapshot, now: now, count: 1)[0].events
        let count = events.count
        let rows = max(1, Int((height - 640) / 54))
        let shown = count > rows ? Array(events.prefix(rows - 1)) : events
        return VStack(alignment: .leading, spacing: 14) {
            label(count == 0 ? "TODAY" : "TODAY · \(count) EVENT\(count == 1 ? "" : "S")")
            if events.isEmpty {
                Text("Nothing scheduled")
                    .font(.custom(Face.sans, size: 30).weight(.medium))
                    .foregroundStyle(Ink.faint)
            }
            ForEach(Array(shown.enumerated()), id: \.offset) { _, event in
                row(event)
            }
            if shown.count < count {
                Text("+\(count - shown.count) more")
                    .font(.custom(Face.sans, size: 26).weight(.bold))
                    .foregroundStyle(Ink.red)
            }
        }
    }

    private func row(_ event: CalendarEvent) -> some View {
        let ended = !event.isAllDay && event.end <= now
        let running = !event.isAllDay && event.start <= now && !ended
        return HStack(alignment: .firstTextBaseline, spacing: 18) {
            marker(ended: ended, running: running)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
            Text(event.isAllDay ? "all day" : CompactTime.string(event.start, in: zone))
                .font(.custom(Face.sans, size: 26).weight(.semibold))
                .foregroundStyle(Ink.faint)
                .frame(width: 110, alignment: .leading)
            Text(event.summary)
                .font(.custom(Face.sans, size: 32).weight(.semibold))
                .foregroundStyle(ended ? Ink.faint : Ink.cream)
                .lineLimit(1)
        }
    }

    @ViewBuilder private func marker(ended: Bool, running: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 2)
        if ended {
            shape.stroke(Ink.faint, lineWidth: 2).frame(width: 14, height: 14)
        } else {
            shape.fill(running ? Ink.red : Ink.yellow).frame(width: 14, height: 14)
        }
    }

    private var foot: some View {
        let stamp = snapshot.sources.weather?.fetchedAt ?? snapshot.generatedAt
        return Text("updated \(CompactTime.string(stamp, in: zone))")
            .font(.custom(Face.sans, size: 20).weight(.semibold))
            .foregroundStyle(Ink.faint)
    }
}
