import DashboardCore
import SwiftUI

/// The spiritual successor to the Pi's `halftone_agenda`, as a dark plate for a big screen:
/// the weather and its reading on the left, the day's agenda on the right.
///
/// Cream type on a warm charcoal ground, with the Pi's two Inky spot inks: ochre for the sun,
/// the moon's ring and the lightning, red for the event in progress and the next one up. The
/// weather window is painted at full resolution (`WeatherArt`) from `WeatherScene`'s layout:
/// gradient skies, a glowing sun, shaded clouds, and at night the real moon photograph at
/// tonight's phase. Elapsed events print through a fine dot screen, the one halftone the plate
/// keeps, after the Pi's perforated type. Type is the Pi's own: Righteous for the weather and
/// the agenda's chrome, DM Sans for the events.
struct HalftoneView: View {
    let snapshot: Snapshot
    let now: Date
    let notice: String?

    private var zone: TimeZone { snapshot.timeZone }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let artWidth = (size.width * 0.46).rounded()
            let artHeight = (size.height * 0.6).rounded()
            ZStack(alignment: .topLeading) {
                Print.paper

                // The window bleeds past the screen edge so the burn-in drift never shows one.
                Group {
                    if let weather = snapshot.sources.weather?.data {
                        WeatherArt(
                            icon: weather.currentIcon,
                            moonFraction: snapshot.moon?.today?.fraction,
                            size: CGSize(width: artWidth + 24, height: artHeight + 24)
                        )
                        .equatable()
                    } else {
                        Print.ink.opacity(0.05)
                    }
                }
                .frame(width: artWidth + 24, height: artHeight + 24)
                .clipped()  // before the offset, so the bleed past the top and left survives the drift
                .offset(x: -24, y: -24)
                .overlay(alignment: .topLeading) { alertChip.padding(.leading, 56).padding(.top, 44) }

                WeatherBand(snapshot: snapshot, now: now)
                    .frame(width: artWidth - 56 - 40, height: size.height - artHeight - 28 - 40, alignment: .topLeading)
                    .offset(x: 56, y: artHeight + 28)

                ScreenRule()
                    .frame(width: 10, height: size.height + 48)
                    .offset(x: artWidth, y: -24)

                AgendaPane(snapshot: snapshot, now: now)
                    .frame(width: size.width - artWidth - 10 - 64 - 56, height: size.height - 44 - 40)
                    .offset(x: artWidth + 10 + 64, y: 44)
            }
            .offset(BurnIn.drift(at: now))
        }
        .background(Print.paper)
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            if let notice {
                Text(notice.uppercased())
                    .font(.custom(Print.display, size: 20))
                    .foregroundStyle(Print.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Print.red)
                    .padding(.top, 36)
                    .padding(.trailing, 56)
            }
        }
        .environment(\.timeZone, zone)
    }

    @ViewBuilder private var alertChip: some View {
        if let alert = snapshot.sources.weather?.data?.alerts.first {
            Text(alert.event.uppercased())
                .font(.custom(Print.display, size: 26))
                .foregroundStyle(Print.ink)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Print.red)
        }
    }
}

/// The plate's inks and faces. `paper` is the ground and `ink` the type, so the inverted
/// treatments (the running event, the TOMORROW chip) read the same as on the Pi's light plate.
enum Print {
    static let paper = Color(red: 0.080, green: 0.076, blue: 0.088)
    static let ink = Color(red: 0.925, green: 0.895, blue: 0.835)
    static let red = Color(red: 0.88, green: 0.33, blue: 0.25)
    static let ochre = Color(red: 0.92, green: 0.69, blue: 0.22)
    static let faint = Color(red: 0.925, green: 0.895, blue: 0.835).opacity(0.55)

    static let display = "Righteous-Regular"
    static let text = "DMSans-9ptRegular"
}

// MARK: - The weather window

/// The weather painted at full resolution from `WeatherScene`'s composition. Static (no
/// motion, for the GPU and the panel), and Equatable on what it draws, so the minute ticks
/// never repaint it.
private struct WeatherArt: View, Equatable {
    let icon: String
    let moonFraction: Double?
    let size: CGSize

    var body: some View {
        let scene = WeatherScene(icon: icon, size: size)
        ZStack(alignment: .topLeading) {
            Canvas(rendersAsynchronously: false) { context, _ in
                sky(scene, in: &context)
                if scene.night { stars(scene, in: &context) }
                if !scene.night { sun(scene, in: &context) }
                if scene.night, let (c, r) = scene.body { moonGlow(c, r, in: &context) }
            }
            if scene.night, let (c, r) = scene.body {
                // Tonight's moon, from the photograph, at the phase the Pi reports.
                ZStack {
                    Circle().stroke(Print.ochre.opacity(0.45), lineWidth: max(2, r * 0.02)).padding(-r * 0.06)
                    MoonDisc(fraction: moonFraction ?? 0.5, radius: r)
                }
                .frame(width: r * 2, height: r * 2)
                .position(c)
            }
            Canvas(rendersAsynchronously: false) { context, _ in
                weather(scene, in: &context)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: Sky

    private func palette(_ scene: WeatherScene) -> (top: Color, bottom: Color) {
        if scene.night {
            return (Color(red: 0.03, green: 0.04, blue: 0.09), Color(red: 0.09, green: 0.12, blue: 0.22))
        }
        switch scene.kind {
        case .clear, .fewClouds:
            return (Color(red: 0.07, green: 0.15, blue: 0.28), Color(red: 0.20, green: 0.32, blue: 0.45))
        case .clouds:
            return (Color(red: 0.10, green: 0.15, blue: 0.23), Color(red: 0.24, green: 0.31, blue: 0.39))
        case .mist:
            return (Color(red: 0.17, green: 0.19, blue: 0.22), Color(red: 0.32, green: 0.34, blue: 0.36))
        case .overcast, .snow:
            return (Color(red: 0.15, green: 0.18, blue: 0.22), Color(red: 0.30, green: 0.34, blue: 0.39))
        case .rain:
            return (Color(red: 0.10, green: 0.13, blue: 0.17), Color(red: 0.22, green: 0.27, blue: 0.32))
        case .thunder:
            return (Color(red: 0.07, green: 0.08, blue: 0.11), Color(red: 0.17, green: 0.19, blue: 0.25))
        }
    }

    private func sky(_ scene: WeatherScene, in context: inout GraphicsContext) {
        let (top, bottom) = palette(scene)
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(Gradient(colors: [top, bottom]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height))
        )
    }

    private func stars(_ scene: WeatherScene, in context: inout GraphicsContext) {
        guard scene.kind != .snow else { return }
        var random = SplitMix(seed: 0x5354_4152)  // "STAR"
        let clouds = cloudPath(scene)
        for _ in 0..<140 {
            let p = CGPoint(x: random.unit() * size.width, y: random.unit() * size.height * 0.9)
            let r = 0.6 + pow(random.unit(), 3) * 2.4
            let alpha = 0.25 + random.unit() * 0.6
            guard !clouds.contains(p) else { continue }
            let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            if r > 2 {
                var glow = context
                glow.addFilter(.blur(radius: r * 2))
                glow.fill(dot, with: .color(Print.ink.opacity(alpha * 0.6)))
            }
            context.fill(dot, with: .color(Print.ink.opacity(alpha)))
        }
    }

    // MARK: Sun and moon

    private func sun(_ scene: WeatherScene, in context: inout GraphicsContext) {
        guard let (c, r) = scene.body else { return }
        let dimmed = scene.kind == .mist ? 0.55 : 1.0
        // The glow, then the rays as beams of light fading outward, then the disc.
        context.fill(
            Path(ellipseIn: CGRect(x: c.x - r * 3, y: c.y - r * 3, width: r * 6, height: r * 6)),
            with: .radialGradient(
                Gradient(colors: [Color(red: 0.98, green: 0.62, blue: 0.20).opacity(0.30 * dimmed), Print.ochre.opacity(0)]),
                center: c, startRadius: r * 0.95, endRadius: r * 2.3
            )
        )
        for wedge in scene.rays {
            var beam = Path()
            beam.move(to: wedge[0])
            for p in wedge.dropFirst() { beam.addLine(to: p) }
            beam.closeSubpath()
            context.fill(beam, with: .linearGradient(
                Gradient(colors: [Color(red: 1, green: 0.86, blue: 0.55).opacity(0.7 * dimmed), Color(red: 0.98, green: 0.62, blue: 0.20).opacity(0)]),
                startPoint: c, endPoint: wedge[1]
            ))
        }
        let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        context.fill(disc, with: .radialGradient(
            Gradient(colors: [
                Color(red: 1, green: 0.97, blue: 0.86).opacity(dimmed),
                Color(red: 0.99, green: 0.84, blue: 0.47).opacity(dimmed),
                Print.ochre.opacity(dimmed),
            ]),
            center: CGPoint(x: c.x - r * 0.25, y: c.y - r * 0.25), startRadius: 0, endRadius: r * 1.15
        ))
    }

    private func moonGlow(_ c: CGPoint, _ r: CGFloat, in context: inout GraphicsContext) {
        context.fill(
            Path(ellipseIn: CGRect(x: c.x - r * 2.6, y: c.y - r * 2.6, width: r * 5.2, height: r * 5.2)),
            with: .radialGradient(
                Gradient(colors: [Print.ink.opacity(0.16), Print.ink.opacity(0)]),
                center: c, startRadius: r, endRadius: r * 2.6
            )
        )
    }

    // MARK: Cloud, rain, snow, lightning, mist

    private func cloudPath(_ scene: WeatherScene) -> Path {
        var path = Path()
        for (c, r) in scene.puffs { path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)) }
        return path
    }

    private func cloudColors(_ scene: WeatherScene) -> (lit: Color, shade: Color) {
        if scene.night { return (Color(red: 0.36, green: 0.39, blue: 0.47), Color(red: 0.16, green: 0.18, blue: 0.24)) }
        switch scene.kind {
        case .rain: return (Color(red: 0.62, green: 0.66, blue: 0.71), Color(red: 0.27, green: 0.30, blue: 0.36))
        case .thunder: return (Color(red: 0.48, green: 0.51, blue: 0.57), Color(red: 0.17, green: 0.18, blue: 0.23))
        case .overcast, .snow: return (Color(red: 0.80, green: 0.81, blue: 0.82), Color(red: 0.42, green: 0.45, blue: 0.50))
        default: return (Color(red: 0.98, green: 0.97, blue: 0.95), Color(red: 0.62, green: 0.67, blue: 0.74))
        }
    }

    private func weather(_ scene: WeatherScene, in context: inout GraphicsContext) {
        let unit = min(size.width, size.height)
        var random = SplitMix(seed: 0x5745_4154)  // "WEAT"

        if scene.kind == .mist {
            var bands = context
            bands.addFilter(.blur(radius: unit * 0.03))
            for i in 0..<7 {
                let y = size.height * (0.18 + Double(i) * 0.12)
                let inset = size.width * (0.05 + random.unit() * 0.25)
                let band = Path(roundedRect: CGRect(x: inset, y: y, width: size.width - inset * 1.3, height: unit * 0.045), cornerRadius: unit * 0.02)
                bands.fill(band, with: .color(Print.ink.opacity(0.10 + random.unit() * 0.12)))
            }
        }

        if scene.kind == .rain || scene.kind == .thunder {
            var rain = Path()
            let base = scene.cloudBase - unit * 0.04
            for _ in 0..<220 {
                let x = random.unit() * (size.width + unit * 0.3) - unit * 0.15
                let y = base + random.unit() * (size.height - base)
                let length = unit * (0.04 + random.unit() * 0.05)
                rain.move(to: CGPoint(x: x, y: y))
                rain.addLine(to: CGPoint(x: x - length * 0.3, y: y + length))
            }
            context.stroke(rain, with: .color(Color(red: 0.74, green: 0.83, blue: 0.92).opacity(0.5)),
                           style: StrokeStyle(lineWidth: max(1.6, unit * 0.0035), lineCap: .round))
        }

        if !scene.puffs.isEmpty {
            let cloud = cloudPath(scene)
            let bounds = cloud.boundingRect
            let (lit, shade) = cloudColors(scene)
            // A soft shadow under the bank, then the bank shaded top to bottom, then a
            // brighter crown on each puff for volume.
            var under = context
            under.addFilter(.blur(radius: unit * 0.035))
            under.fill(cloud.offsetBy(dx: 0, dy: unit * 0.03), with: .color(.black.opacity(0.28)))
            context.fill(cloud, with: .linearGradient(
                Gradient(colors: [lit, shade]),
                startPoint: CGPoint(x: bounds.midX, y: bounds.minY),
                endPoint: CGPoint(x: bounds.midX, y: bounds.maxY)
            ))
            var crowns = context
            crowns.clip(to: cloud)
            crowns.addFilter(.blur(radius: unit * 0.02))
            for (c, r) in scene.puffs {
                crowns.fill(
                    Path(ellipseIn: CGRect(x: c.x - r * 0.7, y: c.y - r * 0.95, width: r * 1.4, height: r * 1.0)),
                    with: .color(lit.opacity(0.55))
                )
            }
        }

        let bolt = scene.bolt
        if let first = bolt.first {
            var path = Path()
            path.move(to: first)
            for p in bolt.dropFirst() { path.addLine(to: p) }
            path.closeSubpath()
            var glow = context
            glow.addFilter(.blur(radius: unit * 0.03))
            glow.fill(path, with: .color(Print.ochre.opacity(0.8)))
            context.fill(path, with: .linearGradient(
                Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.75), Print.ochre]),
                startPoint: path.boundingRect.origin,
                endPoint: CGPoint(x: path.boundingRect.maxX, y: path.boundingRect.maxY)
            ))
        }

        if scene.kind == .snow {
            let base = scene.cloudBase - unit * 0.02
            for _ in 0..<130 {
                let p = CGPoint(x: random.unit() * size.width, y: base + random.unit() * (size.height - base))
                let depth = random.unit()
                let r = unit * (0.003 + depth * 0.009)
                let flake = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                var soft = context
                if depth < 0.4 { soft.addFilter(.blur(radius: r * 0.8)) }
                soft.fill(flake, with: .color(Print.ink.opacity(0.55 + depth * 0.45)))
            }
        }
    }
}

/// The full-height rule between the panes: a narrow strip of fine screen.
private struct ScreenRule: View {
    var body: some View {
        Canvas { context, size in
            let p: CGFloat = 4
            var path = Path()
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? 0 : p / 2
                while x < size.width {
                    path.addEllipse(in: CGRect(x: x, y: y, width: 2.6, height: 2.6))
                    x += p
                }
                y += p / 2
                row += 1
            }
            context.fill(path, with: .color(Print.ink.opacity(0.35)))
        }
    }
}

// MARK: - The weather band

private struct WeatherBand: View {
    let snapshot: Snapshot
    let now: Date
    @Environment(\.timeZone) private var zone

    var body: some View {
        if let weather = snapshot.sources.weather?.data {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 34) {
                    Text("\(Int(weather.currentTemp.rounded()))°")
                        .font(.custom(Print.display, size: 168))
                        .foregroundStyle(Print.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .layoutPriority(1)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(weather.currentDescription.uppercased())
                            .font(.custom(Print.display, size: 38))
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                        Text("H \(Int(weather.high.rounded()))°  ·  L \(Int(weather.low.rounded()))°")
                            .font(.custom(Print.text, size: 36).weight(.semibold))
                    }
                    .foregroundStyle(Print.ink)
                }
                Rectangle().fill(Print.ink).frame(height: 2)
                HStack {
                    if let rise = weather.sunrise { sun("sunrise", rise) }
                    Spacer()
                    if let set = weather.sunset { sun("sunset", set) }
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(dateline)
                        .font(.custom(Print.display, size: 32))
                    Spacer()
                    Text(footnote(weather))
                        .font(.custom(Print.text, size: 24).weight(.semibold))
                        .tracking(1.5)
                }
                .foregroundStyle(Print.ink)
            }
        } else {
            Text("NO WEATHER YET")
                .font(.custom(Print.display, size: 40))
                .foregroundStyle(Print.faint)
        }
    }

    private func sun(_ symbol: String, _ date: Date) -> some View {
        Label {
            Text(date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)))
                .font(.custom(Print.text, size: 32).weight(.semibold))
        } icon: {
            Image(systemName: symbol).font(.system(size: 30, weight: .semibold))
        }
        .foregroundStyle(Print.ink)
    }

    /// "WED · OCT 14 · 2026".
    private var dateline: String {
        let style = Date.FormatStyle(timeZone: zone)
        let weekday = now.formatted(style.weekday(.abbreviated))
        let monthDay = now.formatted(style.month(.abbreviated).day())
        let year = now.formatted(style.year())
        return "\(weekday) · \(monthDay) · \(year)".uppercased()
    }

    private func footnote(_ weather: Weather) -> String {
        var parts: [String] = []
        if let feels = weather.feelsLike { parts.append("FEELS \(Int(feels.rounded()))°") }
        if let aqi = snapshot.sources.airQuality?.data { parts.append("AQI \(aqi.aqi)") }
        return parts.joined(separator: "  ·  ")
    }
}

// MARK: - The agenda

private struct AgendaPane: View {
    let snapshot: Snapshot
    let now: Date
    @Environment(\.timeZone) private var zone

    var body: some View {
        let (day, tomorrow) = Agenda.halftoneDay(from: snapshot, now: now)
        let rows = day.birthdays.map(Row.birthday) + day.events.map(Row.event)
        let next = day.events.first { !$0.isAllDay && $0.start > now }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                if tomorrow {
                    Text("TOMORROW")
                        .font(.custom(Print.display, size: 48))
                        .foregroundStyle(Print.paper)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 2)
                        .background(Print.ink)
                } else {
                    Text("TODAY")
                        .font(.custom(Print.display, size: 56))
                        .foregroundStyle(Print.ink)
                }
                Spacer()
                Text(count(day.events.count))
                    .font(.custom(Print.text, size: 24).weight(.bold))
                    .tracking(2)
                    .foregroundStyle(Print.ink)
            }
            Rectangle().fill(Print.ink).frame(height: 4).padding(.top, 10).padding(.bottom, 26)

            ViewThatFits(in: .vertical) {
                ForEach((0...rows.count).reversed(), id: \.self) { shown in
                    list(Array(rows.prefix(shown)), hidden: rows.count - shown, next: next)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                if let fetched = snapshot.sources.events?.fetchedAt {
                    Text("updated \(fetched.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)).lowercased())")
                        .font(.custom(Print.text, size: 22).weight(.medium))
                        .foregroundStyle(Print.faint)
                }
            }
        }
    }

    private func count(_ n: Int) -> String {
        n == 0 ? "NO EVENTS" : n == 1 ? "1 EVENT" : "\(n) EVENTS"
    }

    @ViewBuilder
    private func list(_ rows: [Row], hidden: Int, next: CalendarEvent?) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            if rows.isEmpty && hidden == 0 {
                Text("A clear day.")
                    .font(.custom(Print.text, size: 40).weight(.medium))
                    .foregroundStyle(Print.faint)
            }
            ForEach(rows) { row in
                switch row {
                case .birthday(let b):
                    BirthdayRow(birthday: b)
                case .event(let e):
                    EventRow(event: e, state: state(of: e, next: next), zone: zone)
                }
            }
            if hidden > 0 {
                Text("+\(hidden) more")
                    .font(.custom(Print.text, size: 28).weight(.bold))
                    .foregroundStyle(Print.ink)
                    .padding(.leading, EventRow.timeWidth + 30)
            }
        }
    }

    private func state(of event: CalendarEvent, next: CalendarEvent?) -> EventRow.State {
        if event.isAllDay { return .upcoming }
        if event.end <= now { return .elapsed }
        if event.start <= now { return .running }
        return event == next ? .next : .upcoming
    }

    enum Row: Identifiable {
        case birthday(Birthday)
        case event(CalendarEvent)

        var id: String {
            switch self {
            case .birthday(let b): return "b-\(b.name)"
            case .event(let e): return "e-\(e.summary)-\(e.start.timeIntervalSince1970)"
            }
        }
    }
}

private struct EventRow: View {
    enum State { case elapsed, running, next, upcoming }

    let event: CalendarEvent
    let state: State
    let zone: TimeZone

    static let timeWidth: CGFloat = 150

    var body: some View {
        let inverted = state == .running
        let ink = Print.ink
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .trailing, spacing: 2) {
                if event.isAllDay {
                    Text("ALL DAY").font(.custom(Print.text, size: 24).weight(.bold)).tracking(1.5)
                } else {
                    Text("\(CompactTime.string(event.start, in: zone)) –")
                    Text(CompactTime.string(event.end, in: zone))
                }
            }
            .font(.custom(Print.text, size: 30).weight(.semibold))
            .foregroundStyle(ink)
            .frame(width: Self.timeWidth, alignment: .trailing)
            .perforated(state == .elapsed)

            Rectangle()
                .fill(state == .running || state == .next ? Print.red : .clear)
                .frame(width: 7)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.summary)
                    .font(.custom(Print.text, size: 44).weight(.bold))
                    .foregroundStyle(ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .perforated(state == .elapsed)
                if let location = event.shortLocation {
                    Text(location)
                        .font(.custom(Print.text, size: 28).weight(.medium))
                        .foregroundStyle(inverted ? Print.ink.opacity(0.75) : Print.faint)
                        .lineLimit(1)
                        .perforated(state == .elapsed)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, inverted ? 14 : 0)
        .padding(.trailing, inverted ? 18 : 0)
        // On the dark plate "inverted" is a quiet lift, not a cream bar: the brightest block on
        // a big screen should not be a meeting.
        .background(inverted ? Print.ink.opacity(0.1) : .clear)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct BirthdayRow: View {
    let birthday: Birthday

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Image(systemName: "gift.fill")
                .font(.system(size: 30))
                .foregroundStyle(Print.red)
                .frame(width: EventRow.timeWidth, alignment: .trailing)
            Rectangle().fill(.clear).frame(width: 7)
            Text(birthday.age.map { "\(birthday.name) turns \($0)" } ?? "\(birthday.name)'s birthday")
                .font(.custom(Print.text, size: 40).weight(.bold))
                .foregroundStyle(Print.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - Perforated type

extension View {
    /// Prints this view through a fine dot screen, as the Pi perforates elapsed events.
    @ViewBuilder func perforated(_ on: Bool) -> some View {
        if on {
            self.hidden().overlay(DotScreen().mask(self))
        } else {
            self
        }
    }
}

/// A fine, even screen of ink dots.
private struct DotScreen: View {
    var body: some View {
        Canvas { context, size in
            let p: CGFloat = 4.2
            var path = Path()
            var y: CGFloat = 0
            var row = 0
            while y < size.height + p {
                var x: CGFloat = row.isMultiple(of: 2) ? 0 : p / 2
                while x < size.width + p {
                    path.addEllipse(in: CGRect(x: x - 1.35, y: y - 1.35, width: 2.7, height: 2.7))
                    x += p
                }
                y += p * 0.87
                row += 1
            }
            context.fill(path, with: .color(Print.ink.opacity(0.6)))
        }
    }
}

/// A small deterministic generator for the star and snow fields.
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> CGFloat { CGFloat(Double(next() >> 11) / Double(1 << 53)) }
}
