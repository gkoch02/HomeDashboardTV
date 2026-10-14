import DashboardCore
import SwiftUI

/// The spiritual successor to the Pi's `halftone_agenda`: a print plate on warm newsprint.
/// The weather engraving and its reading on the left, the day's agenda on the right.
///
/// What the TV adds: the engraving is a true AM halftone (round dots on a 45° screen, sized by
/// tone, `HalftoneScene`) instead of an error-diffusion dither, and the plate prints in black
/// plus two spot inks after the Pi's Inky palette: ochre rings the sun and moon and draws the
/// lightning, red marks the event in progress and the next one up. Elapsed events print in a
/// fine dot screen, the TV's take on the Pi's perforated type. Type is the Pi's own: Righteous
/// for the weather and the agenda's chrome, DM Sans for the events.
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

                // The engraving bleeds past the screen edge so the burn-in drift never shows one.
                Group {
                    if let weather = snapshot.sources.weather?.data {
                        HalftoneArt(icon: weather.currentIcon, size: CGSize(width: artWidth + 24, height: artHeight + 24))
                            .equatable()
                    } else {
                        Print.ink.opacity(0.06)
                    }
                }
                .frame(width: artWidth + 24, height: artHeight + 24)
                .offset(x: -24, y: -24)
                .clipped()
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
                    .foregroundStyle(Print.paper)
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
                .foregroundStyle(Print.paper)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Print.red)
        }
    }
}

/// The plate's inks and faces.
enum Print {
    static let paper = Color(red: 0.945, green: 0.925, blue: 0.882)
    static let ink = Color(red: 0.11, green: 0.11, blue: 0.125)
    static let red = Color(red: 0.84, green: 0.25, blue: 0.20)
    static let ochre = Color(red: 0.90, green: 0.66, blue: 0.13)
    static let faint = Color(red: 0.11, green: 0.11, blue: 0.125).opacity(0.55)

    static let display = "Righteous-Regular"
    static let text = "DMSans-9ptRegular"
}

// MARK: - The engraving

/// The weather scene screened as an AM halftone, with its crisp linework drawn over the dots.
/// Equatable on what it draws, so the clock's minute ticks never re-screen it.
private struct HalftoneArt: View, Equatable {
    let icon: String
    let size: CGSize

    /// Screen ruling: dot pitch in points. Fine enough to read as tone across a room, coarse
    /// enough that the dots are the point up close.
    private static let pitch: CGFloat = 6.5

    var body: some View {
        let scene = HalftoneScene(icon: icon, size: size)
        Canvas(rendersAsynchronously: false) { context, _ in
            screen(scene, in: &context)
            linework(scene, in: &context)
        }
        .frame(width: size.width, height: size.height)
    }

    /// Dots on a 45° grid, each covering its cell in proportion to the tone there.
    private func screen(_ scene: HalftoneScene, in context: inout GraphicsContext) {
        let p = Self.pitch
        let diagonal = hypot(size.width, size.height)
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let cosA = cos(Double.pi / 4), sinA = sin(Double.pi / 4)
        var path = Path()
        var v = -diagonal / 2
        while v <= diagonal / 2 {
            var u = -diagonal / 2
            while u <= diagonal / 2 {
                let x = c.x + CGFloat(cosA) * u - CGFloat(sinA) * v
                let y = c.y + CGFloat(sinA) * u + CGFloat(cosA) * v
                if x > -p, y > -p, x < size.width + p, y < size.height + p {
                    let t = scene.tone(at: CGPoint(x: x, y: y))
                    if t > 0.012 {
                        // Dot area = tone x cell area; past ~80% the dots merge into solid.
                        let r = min(p * 0.72, p * CGFloat((t / Double.pi).squareRoot()) * 1.06)
                        path.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    }
                }
                u += p
            }
            v += p
        }
        context.fill(path, with: .color(Print.ink))
    }

    /// What must stay sharp: the sun or moon's ring, stars, snow, the lightning.
    private func linework(_ scene: HalftoneScene, in context: inout GraphicsContext) {
        let unit = min(size.width, size.height)
        // The sun or moon sits behind the cloud: its linework stops at the cloud's edge.
        var cloud = Path()
        for (c, r) in scene.puffs { cloud.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)) }
        var behind = context
        if !scene.puffs.isEmpty { behind.clip(to: cloud, options: .inverse) }
        var rays = Path()
        for wedge in scene.rays {
            rays.move(to: wedge[0])
            for p in wedge.dropFirst() { rays.addLine(to: p) }
            rays.closeSubpath()
        }
        behind.fill(rays, with: .color(Print.paper))
        behind.stroke(rays, with: .color(Print.ink), style: StrokeStyle(lineWidth: max(2.5, unit * 0.004), lineJoin: .round))
        if let (c, r) = scene.body {
            let ring = Path(ellipseIn: CGRect(x: c.x - r - 3, y: c.y - r - 3, width: (r + 3) * 2, height: (r + 3) * 2))
            behind.stroke(ring, with: .color(Print.ochre), lineWidth: max(4, unit * 0.008))
        }
        var random = SplitMix(seed: 0x4854_4F4E)  // "HTON"
        if scene.night && scene.kind != .snow {
            var stars = Path()
            for _ in 0..<70 {
                let x = random.unit() * size.width, y = random.unit() * size.height * 0.85
                let p = CGPoint(x: x, y: y)
                guard scene.tone(at: p) > 0.6 else { continue }  // open sky only
                let r = 1.2 + random.unit() * 2.2
                stars.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
            context.fill(stars, with: .color(Print.paper))
        }
        if scene.kind == .snow {
            var flakes = Path()
            let base = scene.cloudBase
            for _ in 0..<90 {
                let x = random.unit() * size.width
                let y = base + random.unit() * (size.height - base)
                let r = unit * (0.006 + random.unit() * 0.009)
                flakes.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
            context.fill(flakes, with: .color(Print.paper))
            context.stroke(flakes, with: .color(Print.ink), lineWidth: 1.5)
        }
        let bolt = scene.bolt
        if let first = bolt.first {
            var path = Path()
            path.move(to: first)
            for p in bolt.dropFirst() { path.addLine(to: p) }
            path.closeSubpath()
            context.fill(path, with: .color(Print.ochre))
            context.stroke(path, with: .color(Print.ink), lineWidth: 3)
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
            context.fill(path, with: .color(Print.ink))
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
        let ink = inverted ? Print.paper : Print.ink
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
                        .foregroundStyle(inverted ? Print.paper.opacity(0.8) : Print.faint)
                        .lineLimit(1)
                        .perforated(state == .elapsed)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, inverted ? 14 : 0)
        .padding(.trailing, inverted ? 18 : 0)
        .background(inverted ? Print.ink : .clear)
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
            context.fill(path, with: .color(Print.ink.opacity(0.75)))
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
