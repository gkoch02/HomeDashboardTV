import DashboardCore
import SwiftUI

/// A layout of the TV's own, after IdleHoursTV's `cyberpunk` theme: everything the Pi sends,
/// set as *Cyberpunk 2077*'s Journal. Red Rajdhani on a near-black ground, cyan for what is
/// live, yellow for warnings.
///
/// Across the top, the menu's header: the temperature and the air as the HUD's stat bars, the
/// game's tabs with JOURNAL lit, and the date. Down the left, the clock over the district (the
/// weather's place, or Night City's district for the hour), then the calendar as ACTIVE JOBS
/// (the job under way and the tracked one lit, with the cursor parked on it) and the fortnight's
/// birthdays as CONTACTS. On the right, the scan of the weather now (its description breaking
/// out of hex, the temperature and six readouts over bars), the next 24 hours as a signal trace,
/// the five-day forecast, the day's quote as an encrypted shard, and the moon. Along the foot,
/// each source's sync status and the key hint.
///
/// The screen boots as the game's menus do: the rule runs out from the middle, each panel
/// flickers on, and the headings break out of hex. Settled, now and then the clock glitches
/// with a cyan ghost (not under Reduce Motion).
///
/// Drawn at 1920 x 1080 and scaled to the screen.
struct CyberpunkView: Theme {
    let snapshot: Snapshot
    let now: Date

    static let fullBleed = true

    @Environment(DashboardStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var boot = Boot.dark
    @State private var glitch = false

    private static let size = CGSize(width: 1920, height: 1080)

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / Self.size.width, geometry.size.height / Self.size.height)
            // The timeline runs only while the menu boots: at rest the screen stays still.
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !boot.isBooting)) { context in
                screen(t: boot.elapsed(at: context.date))
                    .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
                    .scaleEffect(scale)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .onBuildIn(reset: { settled in boot = settled ? .done : .dark }) {
            let start = Date.now
            boot = .booting(start)
            DispatchQueue.main.asyncAfter(deadline: .now() + Boot.duration) {
                if boot == .booting(start) { boot = .done }
            }
        }
        // Its own task, keyed on what allows it, so Reduce Motion turned on later stops it.
        .task(id: boot == .done && !reduceMotion) { await glitches(boot == .done && !reduceMotion) }
    }

    var backdrop: some View { Ground() }

    func notice(_ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text.uppercased()).tracking(22 * 0.08)
        }
        .font(.custom(Face.semibold, size: 22))
        .foregroundStyle(Ink.yellow)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Bevelled(cut: 10).fill(Ink.ground.opacity(0.92)))
        .overlay(Bevelled(cut: 10).stroke(Ink.yellow, lineWidth: 1.5))
    }

    /// Now and then, a glitch of the clock; none unless *active*, and none left showing when
    /// the loop is cancelled mid-glitch.
    private func glitches(_ active: Bool) async {
        defer { glitch = false }
        guard active else { return }
        do {
            while true {
                try await Task.sleep(for: .seconds(Double.random(in: 9...16)))
                glitch = true
                try await Task.sleep(for: .milliseconds(140))
                glitch = false
            }
        } catch {}
    }

    // MARK: The screen

    private func screen(t: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Header(snapshot: snapshot, now: now, t: t)
                .frame(height: 70)
            Rule(t: t)
                .padding(.horizontal, -Metrics.margin)
                .frame(height: 44)
            HStack(alignment: .top, spacing: Metrics.gutter) {
                LeftColumn(snapshot: snapshot, now: now, t: t, glitch: glitch)
                    .frame(width: Metrics.leftWidth, height: Metrics.bodyHeight, alignment: .topLeading)
                RightColumn(snapshot: snapshot, now: now, t: t,
                            previousPressure: store.pressureHistory.previous(now: now))
                    .frame(maxWidth: .infinity, maxHeight: Metrics.bodyHeight, alignment: .topLeading)
            }
            Spacer(minLength: 0)
            Footer(snapshot: snapshot, now: now)
                .flicker(t, at: 1.0)
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 34)
        .padding(.bottom, 30)
    }
}

// MARK: - The boot

/// Where the menu's boot is: dark before it, booting from a moment, done at rest.
private enum Boot: Equatable {
    case dark, booting(Date), done

    /// Long enough for the last panel and heading to land.
    static let duration = 2.6

    var isBooting: Bool {
        if case .booting = self { true } else { false }
    }

    /// Seconds since the boot began: before everything when dark, after it all when done.
    func elapsed(at date: Date) -> Double {
        switch self {
        case .dark: -1
        case .booting(let start): date.timeIntervalSince(start)
        case .done: .infinity
        }
    }
}

extension View {
    /// Dark until *at*, then a stutter, as a panel finding its feed.
    fileprivate func flicker(_ t: Double, at: Double) -> some View {
        let d = t - at
        let level: Double = d < 0 ? 0 : d < 0.05 ? 0.8 : d < 0.11 ? 0.1 : 1
        return opacity(level)
    }
}

/// A heading breaking out of hex from *at*, locked a little under a second later.
private func decrypted(_ text: String, t: Double, at: Double) -> String {
    let progress = (t - at) / 0.9
    if progress >= 1 { return text }
    return Cyberpunk.decrypt(text, progress: max(0, progress), seed: Cyberpunk.seed(text), frame: Int(max(0, t) * 18))
}

// MARK: - Inks, faces, geometry

private enum Ink {
    static let ground = rgb(0x0B, 0x08, 0x0A)
    static let glow = rgb(0x36, 0x10, 0x15)
    static let red = rgb(0xFF, 0x5E, 0x55)
    static let redHot = rgb(0xFF, 0x8F, 0x84)
    static let redDim = rgb(0x9A, 0x3A, 0x36)
    static let redDeep = rgb(0x4A, 0x13, 0x16)
    static let cyan = rgb(0x5E, 0xF6, 0xFF)
    static let yellow = rgb(0xF2, 0xE2, 0x2E)
    static let green = rgb(0x6F, 0xE0, 0x7A)
    static let well = rgb(0x12, 0x0A, 0x0D)

    static func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    /// The air's colour: green in good air, yellow in moderate, red beyond.
    static func air(_ band: AirQuality.Band) -> Color {
        switch band {
        case .good: green
        case .moderate: yellow
        default: red
        }
    }

    /// A source's sync light.
    static func staleness(_ s: Staleness?) -> Color {
        switch s {
        case .fresh: green
        case .aging: yellow
        case .stale, .expired: red
        case .unknown, nil: redDim
        }
    }
}

private enum Face {
    static let medium = "Rajdhani-Medium"
    static let semibold = "Rajdhani-SemiBold"
    static let bold = "Rajdhani-Bold"
}

private enum Metrics {
    static let margin: CGFloat = 64
    static let gutter: CGFloat = 48
    static let leftWidth: CGFloat = 540
    /// From under the rule to over the footer.
    static let bodyHeight: CGFloat = 852
    static let paneGap: CGFloat = 16
}

/// Rajdhani in capitals, tracked as the game's legends are.
private struct Legend: View {
    let text: String
    var size: CGFloat
    var face = Face.semibold
    var colour = Ink.red
    var tracking: CGFloat = 0.08

    init(_ text: String, size: CGFloat, face: String = Face.semibold, colour: Color = Ink.red, tracking: CGFloat = 0.08) {
        self.text = text
        self.size = size
        self.face = face
        self.colour = colour
        self.tracking = tracking
    }

    var body: some View {
        Text(text.uppercased())
            .font(.custom(face, size: size))
            .tracking(size * tracking)
            .foregroundStyle(colour)
            .lineLimit(1)
    }
}

extension View {
    /// A neon bloom in *colour* behind the view.
    fileprivate func bloom(_ colour: Color, radius: CGFloat, opacity: Double = 0.6) -> some View {
        shadow(color: colour.opacity(opacity), radius: radius)
    }
}

/// A rect with its bottom-right corner cut at 45°, the game's panel shape.
private struct Bevelled: Shape {
    var cut: CGFloat

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - cut))
        p.addLine(to: CGPoint(x: r.maxX - cut, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// A pane of the database: a dark well under a red hairline, its title in the fine print at
/// its top, and a red tab on its top edge.
private struct Pane<Content: View>: View {
    let title: String
    var code: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Mark()
                Legend(title, size: 18, colour: Ink.red, tracking: 0.14)
                Spacer(minLength: 0)
                if let code { Legend(code, size: 14, colour: Ink.redDim, tracking: 0.12) }
            }
            content
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Bevelled(cut: 18).fill(Ink.well.opacity(0.78)))
        .overlay(Bevelled(cut: 18).stroke(Ink.red.opacity(0.32), lineWidth: 1.2))
        .overlay(alignment: .topLeading) {
            Rectangle().fill(Ink.red).frame(width: 64, height: 3).offset(y: -1)
        }
    }
}

/// The fine print's mark: three stepped bars.
private struct Mark: View {
    var colour = Ink.redDim

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(0..<3, id: \.self) { k in
                Rectangle().fill(colour).frame(width: 26 - CGFloat(k) * 8, height: 4)
            }
        }
    }
}

/// A readout's bar: the track, and the fill to *fraction*.
private struct Bar: View {
    let fraction: Double
    var colour = Ink.red
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(colour.opacity(0.18))
                Rectangle().fill(colour).frame(width: g.size.width * min(max(fraction, 0), 1))
                    .bloom(colour, radius: 4, opacity: 0.5)
            }
        }
        .frame(height: height)
    }
}

// MARK: - The ground

/// Near-black with a red haze behind the panes, faint scanlines, the tick rails the game's menus
/// run down both sides, and a vignette. Still, behind the drifting plate.
private struct Ground: View {
    var body: some View {
        Canvas { gc, size in
            let r = CGRect(origin: .zero, size: size)
            gc.fill(Path(r), with: .color(Ink.ground))
            gc.fill(Path(r), with: .radialGradient(
                Gradient(colors: [Ink.glow.opacity(0.9), Ink.glow.opacity(0.3), .clear]),
                center: CGPoint(x: size.width * 0.6, y: size.height * 0.48),
                startRadius: 0, endRadius: size.width * 0.6))
            var scan = Path()
            let step = max(3, size.height / 360)
            var y: CGFloat = 0
            while y < size.height {
                scan.addRect(CGRect(x: 0, y: y, width: size.width, height: step * 0.3))
                y += step
            }
            gc.fill(scan, with: .color(.black.opacity(0.2)))
            // The rails: a tick every few points, a long one every fifth.
            let unit = size.height / 1080
            for x in [22 * unit, size.width - 22 * unit] {
                var ticks = Path()
                var k = 0
                var ty = size.height * 0.16
                while ty < size.height * 0.88 {
                    let w = (k % 5 == 0 ? 14 : 7) * unit
                    ticks.addRect(CGRect(x: x < size.width / 2 ? x : x - w, y: ty, width: w, height: 1.5 * unit))
                    ty += 13 * unit
                    k += 1
                }
                gc.fill(ticks, with: .color(Ink.redDim.opacity(0.7)))
                let rail = x < size.width / 2 ? x - 7 * unit : x + 5 * unit
                gc.fill(Path(CGRect(x: rail, y: size.height * 0.16, width: 1.5 * unit, height: size.height * 0.72)),
                        with: .color(Ink.redDim.opacity(0.4)))
            }
            gc.fill(Path(r), with: .radialGradient(
                Gradient(colors: [.clear, .black.opacity(0.6)]),
                center: CGPoint(x: size.width / 2, y: size.height / 2),
                startRadius: size.height * 0.5, endRadius: max(size.width, size.height) * 0.62))
        }
        .background(Ink.ground)
    }
}

// MARK: - The header

/// The temperature and the air as the HUD's stat bars, the tabs, and the date.
private struct Header: View {
    let snapshot: Snapshot
    let now: Date
    let t: Double

    var body: some View {
        let zone = snapshot.timeZone
        ZStack {
            HStack(alignment: .bottom, spacing: 44) {
                if let weather = snapshot.sources.weather?.data {
                    stat("\(Int(weather.currentTemp.rounded()))°", "TEMP", Ink.cyan,
                         Cyberpunk.fraction(weather.currentTemp, low: weather.low, high: weather.high))
                }
                if let air = snapshot.sources.airQuality?.data {
                    stat("\(air.aqi)", "AIR · \(air.shortLabel)", Ink.air(air.band), Double(air.aqi) / 300)
                }
                Spacer(minLength: 0)
            }
            .flicker(t, at: 0.2)
            Tabs()
                .flicker(t, at: 0.25)
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Spacer(minLength: 0)
                Legend(now.formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated)), size: 24, colour: Ink.yellow)
                Legend(now.formatted(Date.FormatStyle(timeZone: zone).day().month(.abbreviated).year()),
                       size: 36, face: Face.bold, colour: Ink.red, tracking: 0.04)
            }
            .flicker(t, at: 0.3)
        }
    }

    private func stat(_ value: String, _ label: String, _ colour: Color, _ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(value)
                    .font(.custom(Face.bold, size: 42))
                    .foregroundStyle(colour)
                    .monospacedDigit()
                Legend(label, size: 20, colour: colour, tracking: 0.06)
            }
            Bar(fraction: fraction, colour: colour, height: 4)
        }
        .fixedSize()
    }
}

/// The game's menu tabs, JOURNAL lit, between the shoulder-button keys.
private struct Tabs: View {
    static let names = ["MAP", "CHARACTER", "JOURNAL", "CRAFTING", "INVENTORY"]

    var body: some View {
        HStack(spacing: 40) {
            key("1")
            ForEach(Array(Self.names.enumerated()), id: \.offset) { i, name in
                let lit = name == "JOURNAL"
                HStack(spacing: 10) {
                    TabIcon(index: i)
                        .stroke(lit ? Ink.cyan : Ink.red.opacity(0.9), lineWidth: 1.8)
                        .frame(width: 16, height: 16)
                    Legend(name, size: 19, colour: lit ? Ink.cyan : Ink.red.opacity(0.9), tracking: 0.06)
                }
                .bloom(Ink.cyan, radius: lit ? 8 : 0, opacity: lit ? 0.6 : 0)
            }
            key("3")
        }
        .padding(.top, 14)
    }

    private func key(_ label: String) -> some View {
        Legend(label, size: 18, colour: Ink.cyan, tracking: 0)
            .frame(width: 30, height: 27)
            .overlay(Rectangle().stroke(Ink.cyan.opacity(0.7), lineWidth: 1.5))
    }
}

/// The tabs' small glyphs: a waypoint, a portrait, a page, a hexagon, a diamond.
private struct TabIcon: Shape {
    let index: Int

    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY), s = r.width / 2
        var p = Path()
        switch index {
        case 0, 4:
            p.move(to: CGPoint(x: c.x, y: c.y - s)); p.addLine(to: CGPoint(x: c.x + s, y: c.y))
            p.addLine(to: CGPoint(x: c.x, y: c.y + s)); p.addLine(to: CGPoint(x: c.x - s, y: c.y)); p.closeSubpath()
            if index == 4 { p.addRect(CGRect(x: c.x - 1.5, y: c.y - 1.5, width: 3, height: 3)) }
        case 1:
            p.addEllipse(in: r)
            p.addEllipse(in: CGRect(x: c.x - 2, y: c.y - 4, width: 4, height: 4))
        case 2:
            p.addRect(r)
            for k in 0..<3 {
                let y = c.y - 3.5 + CGFloat(k) * 3.5
                p.move(to: CGPoint(x: c.x - 4, y: y)); p.addLine(to: CGPoint(x: c.x + 4, y: y))
            }
        default:
            for k in 0..<6 {
                let a = Double(k) * .pi / 3 + .pi / 6
                let pt = CGPoint(x: c.x + s * cos(a), y: c.y + s * sin(a))
                k == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
            p.closeSubpath()
        }
        return p
    }
}

/// The header's rule across the screen, running out from the middle as the menu boots, a
/// cyan run under JOURNAL and DATABASE beneath it.
private struct Rule: View {
    let t: Double

    var body: some View {
        let grow = min(max((t - 0.05) / 0.4, 0), 1)
        let eased = 1 - pow(1 - grow, 3)
        VStack(spacing: 6) {
            ZStack {
                Rectangle().fill(Ink.red).frame(height: 2).bloom(Ink.red, radius: 5, opacity: 0.7)
                Rectangle().fill(Ink.cyan).frame(width: 170, height: 4).bloom(Ink.cyan, radius: 6)
            }
            .scaleEffect(x: max(eased, 0.001), anchor: .center)
            Legend("DATABASE", size: 16, colour: Ink.red.opacity(0.85), tracking: 0.14)
                .flicker(t, at: 0.4)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 6)
    }
}

// MARK: - The left column

/// The clock over the district, then the jobs and the contacts.
private struct LeftColumn: View {
    let snapshot: Snapshot
    let now: Date
    let t: Double
    let glitch: Bool

    private static let clockHeight: CGFloat = 238
    private static let headingHeight: CGFloat = 44
    private static let rowHeight: CGFloat = 72
    private static let rowGap: CGFloat = 10
    private static let sectionGap: CGFloat = 26

    var body: some View {
        let contacts = Cyberpunk.contacts(snapshot, now: now, limit: 3)
        let contactsHeight = contacts.isEmpty ? 0 : Self.sectionGap + Self.headingHeight + Self.rowGap
            + CGFloat(contacts.count) * (Self.rowHeight + Self.rowGap)
        let room = Metrics.bodyHeight - Self.clockHeight - Self.headingHeight - Self.rowGap - contactsHeight
        let limit = max(1, Int((room + Self.rowGap) / (Self.rowHeight + Self.rowGap)))
        let jobs = Cyberpunk.jobs(snapshot, now: now, limit: limit)
        VStack(alignment: .leading, spacing: 0) {
            Clock(snapshot: snapshot, now: now, t: t, glitch: glitch)
                .frame(height: Self.clockHeight, alignment: .topLeading)
            Heading(title: "ACTIVE JOBS", chip: true, count: jobs.count)
                .flicker(t, at: 0.35)
            VStack(alignment: .leading, spacing: Self.rowGap) {
                if jobs.isEmpty {
                    Entry(title: "NO ACTIVE JOBS", sub: "CHECK BACK WITH YOUR FIXER", style: .locked)
                        .flicker(t, at: 0.45)
                }
                ForEach(Array(jobs.enumerated()), id: \.element) { i, job in
                    JobRow(job: job, now: now, zone: snapshot.timeZone)
                        .flicker(t, at: 0.42 + Double(i) * 0.06)
                        .offset(x: t < 0.42 + Double(i) * 0.06 + 0.25 ? -24 * (1 - max(0, t - 0.42 - Double(i) * 0.06) / 0.25) : 0)
                }
            }
            .padding(.top, Self.rowGap)
            if !contacts.isEmpty {
                Heading(title: "CONTACTS", chip: false, count: contacts.count)
                    .padding(.top, Self.sectionGap)
                    .flicker(t, at: 0.8)
                VStack(alignment: .leading, spacing: Self.rowGap) {
                    ForEach(Array(contacts.enumerated()), id: \.element) { i, birthday in
                        ContactRow(birthday: birthday, now: now, zone: snapshot.timeZone)
                            .flicker(t, at: 0.86 + Double(i) * 0.06)
                    }
                }
                .padding(.top, Self.rowGap)
            }
        }
    }
}

/// The time, big and red with a bloom, and where it is.
private struct Clock: View {
    let snapshot: Snapshot
    let now: Date
    let t: Double
    let glitch: Bool

    var body: some View {
        let zone = snapshot.timeZone
        let clock = ClockTime.parts(now, in: zone)
        let hour = Calendar.gregorian(in: zone).component(.hour, from: now)
        let place = snapshot.sources.weather?.data?.locationName.map { $0.uppercased() }
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if glitch { face(clock, colour: Ink.cyan).offset(x: -10).opacity(0.7).blendMode(.screen) }
                face(clock, colour: Ink.red)
                    .bloom(Ink.red, radius: 18, opacity: 0.55)
                    .offset(x: glitch ? 6 : 0)
            }
            .flicker(t, at: 0.15)
            HStack(spacing: 12) {
                Diamond().fill(Ink.cyan).frame(width: 12, height: 12)
                Legend(place ?? "NIGHT CITY", size: 24, colour: Ink.cyan, tracking: 0.1)
                Legend("//  \(place == nil ? Cyberpunk.district(hour24: hour) : "DISTRICT")", size: 20,
                       colour: Ink.redDim, tracking: 0.1)
            }
            .padding(.top, -8)
            .flicker(t, at: 0.3)
        }
    }

    private func face(_ clock: (time: String, period: String?), colour: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(clock.time)
                .font(.custom(Face.bold, size: 196))
                .monospacedDigit()
                .kerning(-2)
            if let period = clock.period {
                Text(period).font(.custom(Face.semibold, size: 48))
            }
        }
        .foregroundStyle(colour)
        .frame(height: 190)
    }
}

private struct Diamond: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.midY))
        p.closeSubpath()
        return p
    }
}

/// A category heading in the list: a bevelled bar, a yellow chip for new, the count and a caret.
private struct Heading: View {
    let title: String
    let chip: Bool
    let count: Int

    var body: some View {
        HStack(spacing: 14) {
            Legend(title, size: 22, colour: Ink.red, tracking: 0.06)
            if chip { Rectangle().fill(Ink.yellow).frame(width: 24, height: 11) }
            Spacer(minLength: 0)
            Legend("\(count)", size: 20, colour: Ink.redDim, tracking: 0)
            Caret().stroke(Ink.red, lineWidth: 2).frame(width: 20, height: 12)
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
        .background(Bevelled(cut: 12).fill(Ink.redDeep.opacity(0.4)))
        .overlay(Bevelled(cut: 12).stroke(Ink.red.opacity(0.75), lineWidth: 1.5))
    }
}

private struct Caret: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.closeSubpath()
        return p
    }
}

/// An entry under a heading, inset as the game's are, with the tilted shard glyph at its left.
private struct Entry: View {
    enum Style { case open, live, plain, locked }

    let title: String
    let sub: String
    var subColour: Color?
    let style: Style

    var body: some View {
        let open = style == .open || style == .live
        HStack(spacing: 0) {
            ShardGlyph()
                .fill((open ? Ink.red : Ink.redDim).opacity(open ? 0.85 : 0.5), style: FillStyle(eoFill: true))
                .frame(width: 26, height: 38)
                .frame(width: 70)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.custom(Face.semibold, size: 25))
                    .tracking(25 * 0.03)
                    .foregroundStyle(open ? Color.white.opacity(0.94) : style == .locked ? Ink.red.opacity(0.45) : Ink.red.opacity(0.9))
                    .lineLimit(1)
                Legend(sub, size: 17, colour: subColour ?? (open ? Ink.redHot : Ink.redDim), tracking: 0.1)
            }
            .padding(.leading, 18)
            Spacer(minLength: 12)
            if style == .open {
                // The cyan cursor parked on the tracked job.
                Rectangle().stroke(Ink.cyan, lineWidth: 2)
                    .frame(width: 24, height: 24)
                    .overlay(Rectangle().fill(Ink.cyan.opacity(0.85)).frame(width: 10, height: 10))
                    .bloom(Ink.cyan, radius: 6)
                    .padding(.trailing, 22)
            } else if style == .live {
                Legend("LIVE", size: 16, colour: Ink.ground, tracking: 0.1)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Ink.yellow)
                    .padding(.trailing, 22)
            }
        }
        .frame(height: 72)
        .background(alignment: .trailing) {
            let shape = Bevelled(cut: 14)
            Group {
                if open {
                    shape.fill(LinearGradient(colors: [Ink.red.opacity(0.42), Ink.redDeep.opacity(0.75)],
                                              startPoint: .leading, endPoint: .trailing))
                        .overlay(shape.stroke(Ink.redHot, lineWidth: 1.6))
                        .bloom(Ink.red, radius: 8, opacity: 0.5)
                } else {
                    shape.fill(Ink.well.opacity(0.75))
                        .overlay(shape.stroke(Ink.red.opacity(style == .locked ? 0.25 : 0.45), lineWidth: 1.2))
                }
            }
            .padding(.leading, 70)
        }
    }
}

/// The game's tilted shard card, with its stripes cut through (filled even-odd).
private struct ShardGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.2, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.1))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.2, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - r.height * 0.1))
        p.closeSubpath()
        for k in 0..<3 {
            let y = r.minY + r.height * (0.3 + 0.2 * CGFloat(k))
            p.addRect(CGRect(x: r.minX + r.width * 0.2, y: y, width: r.width * 0.6, height: 2))
        }
        return p
    }
}

/// A calendar event as a job: under way and tracked lit, the rest in the well, tomorrow's dim.
private struct JobRow: View {
    let job: Cyberpunk.Job
    let now: Date
    let zone: TimeZone

    var body: some View {
        let event = job.event
        let place = event.shortLocation.map { "  ·  " + $0 } ?? ""
        switch job.state {
        case .active:
            Entry(title: event.summary, sub: "IN PROGRESS · UNTIL \(clock(event.end, zone))" + place, style: .live)
        case .tracked:
            Entry(title: event.summary, sub: "TRACKED · " + when(event) + place, style: .open)
        case .upcoming:
            Entry(title: event.summary, sub: clock(event.start, zone) + place, style: .plain)
        case .tomorrow:
            Entry(title: event.summary, sub: "TOMORROW " + clock(event.start, zone) + place, style: .locked)
        case .allDay:
            Entry(title: event.summary, sub: "ALL DAY" + place, subColour: Ink.yellow.opacity(0.8), style: .plain)
        }
    }

    /// "IN 25 MIN" within the hour, else the time, "TOMORROW" before it on the next day.
    private func when(_ event: CalendarEvent) -> String {
        let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes < 60 { return "IN \(max(minutes, 0)) MIN" }
        let tomorrow = CivilDate(event.start, in: zone) != CivilDate(now, in: zone)
        return (tomorrow ? "TOMORROW " : "") + clock(event.start, zone)
    }
}

/// A birthday as a contact.
private struct ContactRow: View {
    let birthday: Birthday
    let now: Date
    let zone: TimeZone

    var body: some View {
        let today = CivilDate(now, in: zone)
        let days = Int((birthday.date.start(in: zone).timeIntervalSince(today.start(in: zone)) / 86_400).rounded())
        let when = days == 0 ? "TODAY" : days == 1 ? "TOMORROW"
            : birthday.date.start(in: zone).formatted(Date.FormatStyle(timeZone: zone).weekday(.wide).day().month(.abbreviated))
        let age = birthday.age.map { " · TURNS \($0)" } ?? ""
        Entry(title: birthday.name, sub: "BIRTHDAY · \(when)\(age)",
              subColour: days == 0 ? Ink.yellow : nil, style: days == 0 ? .open : .plain)
    }
}

// MARK: - The right column

private struct RightColumn: View {
    let snapshot: Snapshot
    let now: Date
    let t: Double
    let previousPressure: Double?

    var body: some View {
        let weather = snapshot.sources.weather?.data
        VStack(spacing: Metrics.paneGap) {
            if let weather {
                Conditions(snapshot: snapshot, weather: weather, now: now, t: t, previousPressure: previousPressure)
                    .frame(height: 318)
                    .flicker(t, at: 0.4)
                Trace(snapshot: snapshot, weather: weather, now: now, t: t)
                    .frame(height: 176)
                    .flicker(t, at: 0.55)
                Outlook(snapshot: snapshot, weather: weather, now: now)
                    .frame(height: 124)
                    .flicker(t, at: 0.65)
            } else {
                Pane(title: "SCAN // ATMOSPHERE", code: "NO SIGNAL") {
                    Legend("WEATHER FEED OFFLINE", size: 48, face: Face.bold, colour: Ink.redDim)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: 318 + 176 + 124 + 2 * Metrics.paneGap)
                .flicker(t, at: 0.4)
            }
            HStack(spacing: Metrics.paneGap) {
                Shard(snapshot: snapshot, t: t)
                    .flicker(t, at: 0.75)
                if let moon = snapshot.moon {
                    Lunar(moon: moon, zone: snapshot.timeZone)
                        .frame(width: 400)
                        .flicker(t, at: 0.85)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

/// The weather now: its description breaking out of hex, any alerts, the temperature with the
/// day's range, and six readouts over their bars.
private struct Conditions: View {
    let snapshot: Snapshot
    let weather: Weather
    let now: Date
    let t: Double
    let previousPressure: Double?

    var body: some View {
        let zone = snapshot.timeZone
        let fetched = snapshot.sources.weather?.fetchedAt.map { "SCANNED " + clock($0, zone) } ?? "SCAN"
        Pane(title: "SCAN // ATMOSPHERE", code: fetched) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                Text(decrypted(weather.currentDescription.uppercased(), t: t, at: 0.55))
                    .font(.custom(Face.bold, size: 50))
                    .foregroundStyle(Ink.red)
                    .bloom(Ink.red, radius: 12, opacity: 0.5)
                    .lineLimit(1)
                Spacer(minLength: 0)
                ForEach(weather.alerts.prefix(2), id: \.self) { alert in
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 18, weight: .bold))
                        Legend(alert.event, size: 20, face: Face.bold, colour: Ink.ground, tracking: 0.06)
                    }
                    .foregroundStyle(Ink.ground)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Bevelled(cut: 8).fill(Ink.yellow))
                    .bloom(Ink.yellow, radius: 8, opacity: 0.45)
                }
            }
            ZStack(alignment: .leading) {
                Rectangle().fill(Ink.redDim.opacity(0.7)).frame(height: 1.2)
                Rectangle().fill(Ink.red).frame(width: 80, height: 3)
            }
            HStack(alignment: .center, spacing: 40) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 22) {
                        Image(systemName: WeatherSymbol.name(for: weather.currentIcon))
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 76, weight: .medium))
                            .foregroundStyle(Ink.cyan)
                            .bloom(Ink.cyan, radius: 10, opacity: 0.5)
                            .frame(width: 100)
                        // Rajdhani's degree sign stands well clear of its figures; set apart and pulled in.
                        HStack(alignment: .top, spacing: 2) {
                            Text("\(Int(weather.currentTemp.rounded()))")
                                .font(.custom(Face.bold, size: 132))
                                .monospacedDigit()
                            Text("°")
                                .font(.custom(Face.bold, size: 80))
                                .padding(.top, 30)
                        }
                        .foregroundStyle(Color.white.opacity(0.94))
                        .bloom(Ink.red, radius: 14, opacity: 0.6)
                    }
                    .frame(height: 130)
                    HStack(spacing: 18) {
                        Legend("H \(degrees(weather.high))", size: 26, face: Face.bold, colour: Ink.red)
                        Legend("L \(degrees(weather.low))", size: 26, face: Face.bold, colour: Ink.red)
                        if let feels = weather.feelsLike {
                            Legend("FEELS \(degrees(feels))", size: 26, face: Face.bold, colour: Ink.cyan)
                        }
                    }
                }
                .frame(width: 400, alignment: .leading)
                Grid(horizontalSpacing: 40, verticalSpacing: 16) {
                    let cells = readouts(zone: zone)
                    ForEach(0..<(cells.count + 1) / 2, id: \.self) { row in
                        GridRow {
                            ForEach(cells[(row * 2)..<min(row * 2 + 2, cells.count)], id: \.label) { cell in
                                ReadoutCell(readout: cell)
                            }
                        }
                    }
                }
            }
            .padding(.top, 6)
        }
    }

    private func degrees(_ v: Double) -> String { "\(Int(v.rounded()))°" }

    /// Humidity, pressure, wind, UV, the chance of rain and the sun: what the weather has.
    private func readouts(zone: TimeZone) -> [Readout] {
        var out: [Readout] = [
            Readout(label: "HUMIDITY", value: "\(weather.humidity)%", fraction: Double(weather.humidity) / 100, colour: Ink.cyan),
        ]
        if let p = weather.pressure {
            let trend = Weatherglass.trend(p, from: previousPressure).map { " " + $0 } ?? " HPA"
            out.append(Readout(label: "PRESSURE", value: "\(Int(p.rounded()))\(trend)",
                               fraction: Cyberpunk.fraction(p, low: 970, high: 1050), colour: Ink.red))
        }
        if let speed = weather.windSpeed {
            let compass = weather.windDeg.map { Compass.point($0) + " " } ?? ""
            out.append(Readout(label: "WIND", value: "\(compass)\(Int(speed.rounded())) \(snapshot.isMetric ? "M/S" : "MPH")",
                               fraction: speed / (snapshot.isMetric ? 15 : 35), colour: Ink.red))
        }
        if let uv = weather.uvIndex {
            out.append(Readout(label: "UV INDEX", value: "\(Int(uv.rounded())) \(Weatherglass.uvCategory(uv))",
                               fraction: uv / 11, colour: uv >= 6 ? Ink.yellow : Ink.red))
        }
        let rain = Skylight.ribbon(weather, now: now).first?.precipChance
            ?? Skylight.outlook(weather, now: now, zone: zone, count: 1).first?.precipChance
        if let rain {
            out.append(Readout(label: "PRECIP", value: "\(Int((rain * 100).rounded()))%", fraction: rain, colour: Ink.cyan))
        }
        let suns = Skylight.sunTimes(snapshot, now: now)
        if let rise = suns.first(where: \.rise)?.time, let set = suns.first(where: { !$0.rise })?.time {
            let lit = Cyberpunk.daylight(now: now, rise: rise, set: set)
            out.append(Readout(label: lit == nil ? "NIGHT" : "DAYLIGHT",
                               value: "↑ \(clock(rise, zone))  ↓ \(clock(set, zone))",
                               fraction: lit ?? 0, colour: Ink.yellow))
        }
        return Array(out.prefix(6))
    }
}

private struct Readout {
    let label: String
    let value: String
    let fraction: Double
    let colour: Color
}

private struct ReadoutCell: View {
    let readout: Readout

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Legend(readout.label, size: 16, colour: Ink.redDim, tracking: 0.14)
                Spacer(minLength: 8)
                Legend(readout.value, size: 25, face: Face.bold, colour: readout.colour, tracking: 0.02)
            }
            Bar(fraction: readout.fraction, colour: readout.colour, height: 3)
        }
        .frame(width: 300)
    }
}

/// The next 24 hours as a signal trace: the temperature as a glowing red line through its
/// slots, each slot's reading over it and its time under it, the chance of rain as cyan bars.
private struct Trace: View {
    let snapshot: Snapshot
    let weather: Weather
    let now: Date
    let t: Double

    var body: some View {
        let zone = snapshot.timeZone
        let points = Skylight.ribbon(weather, now: now)
        Pane(title: "SIGNAL // NEXT 24 H", code: "TEMP ━  PRECIP ▮") {
            if points.count < 2 {
                Legend("NO FORECAST SIGNAL", size: 30, face: Face.bold, colour: Ink.redDim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let draw = min(max((t - 0.6) / 0.8, 0), 1)
                Canvas { gc, size in paint(points, zone: zone, draw: draw, in: size, &gc) }
            }
        }
    }

    private func paint(_ points: [Skylight.Point], zone: TimeZone, draw: Double, in size: CGSize, _ gc: inout GraphicsContext) {
        let labelTop: CGFloat = 28, labelBottom: CGFloat = 26
        let plot = CGRect(x: 30, y: labelTop, width: size.width - 60, height: size.height - labelTop - labelBottom)
        let temps = points.map(\.temp)
        let lo = temps.min()!, hi = temps.max()!
        let span = max(hi - lo, 4)
        let mid = (hi + lo) / 2
        func x(_ i: Int) -> CGFloat { plot.minX + plot.width * CGFloat(i) / CGFloat(points.count - 1) }
        func y(_ v: Double) -> CGFloat { plot.midY - CGFloat((v - mid) / span) * plot.height * 0.8 }
        // The grid: faint rows, and a tick at each slot.
        for k in 0...3 {
            let gy = plot.minY + plot.height * CGFloat(k) / 3
            gc.fill(Path(CGRect(x: plot.minX, y: gy, width: plot.width, height: 1)), with: .color(Ink.redDim.opacity(0.18)))
        }
        // The chance of rain, as bars standing on the floor.
        for (i, p) in points.enumerated() where p.precipChance > 0.02 {
            let h = plot.height * CGFloat(p.precipChance)
            gc.fill(Path(CGRect(x: x(i) - 9, y: plot.maxY - h, width: 18, height: h)), with: .color(Ink.cyan.opacity(0.28)))
            gc.fill(Path(CGRect(x: x(i) - 9, y: plot.maxY - h, width: 18, height: 2)), with: .color(Ink.cyan))
        }
        var line = Path()
        for i in points.indices {
            let pt = CGPoint(x: x(i), y: y(points[i].temp))
            i == 0 ? line.move(to: pt) : line.addLine(to: pt)
        }
        let shown = line.trimmedPath(from: 0, to: draw)
        gc.drawLayer { l in
            l.addFilter(.blur(radius: 6))
            l.stroke(shown, with: .color(Ink.red.opacity(0.8)), lineWidth: 5)
        }
        gc.stroke(shown, with: .color(Ink.red), lineWidth: 2.5)
        let reached = Int(Double(points.count - 1) * draw + 0.001)
        let label = Font.custom(Face.bold, size: 22), small = Font.custom(Face.semibold, size: 17)
        for (i, p) in points.enumerated() where i <= reached {
            let c = CGPoint(x: x(i), y: y(p.temp))
            let mark = CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)
            gc.fill(Path(mark), with: .color(p.isNow ? Ink.cyan : Ink.ground))
            gc.stroke(Path(mark), with: .color(p.isNow ? Ink.cyan : Ink.red), lineWidth: 2)
            gc.draw(Text("\(Int(p.temp.rounded()))°").font(label).foregroundColor(p.isNow ? Ink.cyan : .white.opacity(0.9)),
                    at: CGPoint(x: c.x, y: c.y - 12), anchor: .bottom)
            let when = p.isNow ? "NOW" : Self.hour(p.time, zone)
            gc.draw(Text(when).font(small).tracking(1.5).foregroundColor(p.isNow ? Ink.cyan : Ink.redDim),
                    at: CGPoint(x: c.x, y: size.height), anchor: .bottom)
        }
    }

    /// "3 PM" or "15:00".
    private static func hour(_ date: Date, _ zone: TimeZone) -> String {
        let p = ClockTime.parts(date, in: zone)
        guard let period = p.period else { return p.time }
        let h = p.time.split(separator: ":").first.map(String.init) ?? p.time
        return "\(h) \(period)"
    }
}

/// The next five days as bevelled cards: the day, its sky, its high and low and its chance of rain.
private struct Outlook: View {
    let snapshot: Snapshot
    let weather: Weather
    let now: Date

    var body: some View {
        let zone = snapshot.timeZone
        let today = CivilDate(now, in: zone)
        let days = Skylight.outlook(weather, now: now, zone: zone, count: 5)
        HStack(spacing: 12) {
            ForEach(days, id: \.self) { day in
                let isToday = day.date == today
                HStack(spacing: 14) {
                    Image(systemName: WeatherSymbol.name(for: day.icon))
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(isToday ? Ink.cyan : Ink.red)
                        .frame(width: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Legend(isToday ? "TODAY" : day.date.start(in: zone).formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated)),
                               size: 19, colour: isToday ? Ink.cyan : Ink.redDim, tracking: 0.14)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(Int(day.high.rounded()))°")
                                .font(.custom(Face.bold, size: 36))
                                .foregroundStyle(Color.white.opacity(0.92))
                            Text("\(Int(day.low.rounded()))°")
                                .font(.custom(Face.semibold, size: 26))
                                .foregroundStyle(Ink.redDim)
                        }
                        // Always a third line, so every card's figures sit at one height.
                        if let chance = day.precipChance, chance >= 0.1 {
                            Legend("\(Int((chance * 100).rounded()))% RAIN", size: 15, colour: Ink.cyan.opacity(0.85), tracking: 0.1)
                        } else {
                            Legend("DRY", size: 15, colour: Ink.redDim, tracking: 0.1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Bevelled(cut: 14).fill(isToday ? Ink.redDeep.opacity(0.55) : Ink.well.opacity(0.78)))
                .overlay(Bevelled(cut: 14).stroke(isToday ? Ink.redHot : Ink.red.opacity(0.32), lineWidth: isToday ? 1.6 : 1.2))
            }
        }
    }
}

/// The day's quote as an encrypted shard: its digest in the fine print, the text in red, and
/// the author in cyan.
private struct Shard: View {
    let snapshot: Snapshot
    let t: Double

    var body: some View {
        let quote = snapshot.quote ?? snapshot.moon?.quote
        let digest = Cyberpunk.seed(quote?.text ?? "")
        Pane(title: "ENCRYPTED SHARD", code: String(format: "0x%08X // DECRYPTED", UInt32(truncatingIfNeeded: digest))) {
            if let quote {
                VStack(alignment: .leading, spacing: 8) {
                    Text("“\(quote.text)”")
                        .font(.custom(Face.medium, size: 30))
                        .foregroundStyle(Ink.red)
                        .lineSpacing(0)
                        .minimumScaleFactor(0.55)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    Legend("// " + decrypted(quote.author.uppercased(), t: t, at: 0.9), size: 22, face: Face.bold,
                           colour: Ink.cyan, tracking: 0.1)
                        .bloom(Ink.cyan, radius: 6, opacity: 0.5)
                }
            } else {
                Legend("SHARD CORRUPTED", size: 30, face: Face.bold, colour: Ink.redDim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// The moon: its phase lit in red, how much of it, the next full or new, rise and set.
private struct Lunar: View {
    let moon: Moon
    let zone: TimeZone

    var body: some View {
        Pane(title: "LUNAR", code: moon.supermoon ? "SUPERMOON" : nil) {
            HStack(spacing: 22) {
                ZStack {
                    Circle().stroke(Ink.redDim.opacity(0.6), lineWidth: 1.5)
                    if let fraction = moon.today?.fraction {
                        LitShape(fraction: fraction).fill(Ink.red).bloom(Ink.red, radius: 10)
                    }
                }
                .frame(width: 92, height: 92)
                VStack(alignment: .leading, spacing: 5) {
                    Legend(moon.phaseName, size: 25, face: Face.bold, colour: Ink.red, tracking: 0.04)
                    if let lit = moon.today?.illumination {
                        Legend("\(Int(lit.rounded()))% LIT", size: 19, colour: Ink.cyan, tracking: 0.1)
                    }
                    Legend("\(moon.next.isFull ? "FULL" : "NEW") IN \(moon.next.days) D", size: 19, colour: Ink.redDim, tracking: 0.1)
                    if let rise = moon.rise, let set = moon.set {
                        Legend("↑ \(clock(rise, zone))  ↓ \(clock(set, zone))",
                               size: 19, colour: Ink.redDim, tracking: 0.06)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - The footer

/// Fine print and each source's sync light at the left; the key hint at the right.
private struct Footer: View {
    let snapshot: Snapshot
    let now: Date

    var body: some View {
        let s = snapshot.sources
        HStack(spacing: 22) {
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { _ in Rectangle().fill(Ink.redDim).frame(width: 5, height: 14) }
            }
            Legend("NC // 2077 · HOME DASHBOARD SUBNET", size: 15, colour: Ink.redDim, tracking: 0.14)
            ForEach([("CAL", s.events?.staleness), ("WX", s.weather?.staleness),
                     ("AIR", s.airQuality?.staleness), ("BDAY", s.birthdays?.staleness)], id: \.0) { source in
                if let staleness = source.1 {
                    HStack(spacing: 7) {
                        Rectangle().fill(Ink.staleness(staleness)).frame(width: 9, height: 9)
                        Legend(source.0, size: 15, colour: Ink.redDim, tracking: 0.14)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Circle().fill(.white.opacity(0.85)).frame(width: 11, height: 11)
                    .frame(width: 32, height: 27)
                    .overlay(Rectangle().stroke(.white.opacity(0.7), lineWidth: 1.5))
                Text("Settings")
                    .font(.custom(Face.semibold, size: 24))
                    .foregroundStyle(Ink.cyan)
            }
        }
        .frame(height: 34)
    }
}

/// "9:30 AM" or "21:30", in the zone.
private func clock(_ date: Date, _ zone: TimeZone) -> String {
    let p = ClockTime.parts(date, in: zone)
    return p.period.map { "\(p.time) \($0)" } ?? p.time
}

private extension Calendar {
    static func gregorian(in zone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal
    }
}
