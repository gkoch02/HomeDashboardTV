import DashboardCore
import SwiftUI

/// A layout of the TV's own, blended from three of IdleHoursTV's game themes into one terminal:
/// *Deus Ex*'s gold on black, its slab tiles and stat bar; the *Mass Effect* Codex's navy
/// hologram, corner brackets, chronology rows and narration; *Cyberpunk 2077*'s bevelled cuts,
/// hex decrypts, glitches and red for what is urgent.
///
/// The centrepiece is today as an orbit seen at a tilt, turning so that now is always at the
/// front: the hours round its rim, the daylight as a gold arc, and the calendar's next eighteen
/// hours as nodes riding it, labelled where they face the screen. The clock hangs over it as a
/// hologram in a projector's beam, and under it the day's quote is read aloud, Codex fashion,
/// its words lighting as the narrator reaches them.
///
/// Down the left, the agenda as Deus Ex's tiles, the next job on the lit slab and birthdays
/// after it; on the right, the weather as a Codex entry: the description breaking out of hex,
/// the temperature, the next 24 hours as a voice trace, then the readings and the outlook as
/// chronology rows. Along the foot, Deus Ex's stat bar, with the uplink's signal (how many of
/// the Pi's sources are current) as its five pips.
///
/// The terminal boots in: the header decrypts, the tiles slide in, the orbit spins into place,
/// the hologram flickers on and the narration plays. Settled, now and then a gold scan runs
/// down the entry or the hologram glitches (neither under Reduce Motion).
///
/// Drawn at 1920 x 1080 and scaled to the screen.
struct UplinkView: Theme {
    let snapshot: Snapshot
    let now: Date

    static let fullBleed = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var boot = Boot.dark
    @State private var pulse: Pulse?

    private static let size = CGSize(width: 1920, height: 1080)

    private var words: [String] { (snapshot.quote ?? snapshot.moon?.quote)?.text.split(separator: " ").map(String.init) ?? [] }

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / Self.size.width, geometry.size.height / Self.size.height)
            // The timeline runs only while the terminal boots or a pulse plays: at rest it is still.
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !boot.isBooting && pulse == nil)) { context in
                screen(t: boot.elapsed(at: context.date), pulse: pulse?.at(context.date))
                    .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
                    .scaleEffect(scale)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .onBuildIn(reset: { settled in boot = settled ? .done : .dark }) {
            let start = Date.now
            let length = Boot.narrationAt + Uplink.narration(words: words.count) + 0.4
            boot = .booting(start, length: length)
            DispatchQueue.main.asyncAfter(deadline: .now() + length) {
                if boot == .booting(start, length: length) { boot = .done }
            }
        }
        // Its own task, keyed on what allows it, so Reduce Motion turned on later stops it.
        .task(id: boot == .done && !reduceMotion) { await pulses(boot == .done && !reduceMotion) }
    }

    var backdrop: some View { Ground() }

    func notice(_ text: String) -> some View {
        HStack(spacing: 12) {
            Rectangle().fill(Ink.red).frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text("UPLINK DEGRADED").font(Face.cond(18, 700)).tracking(18 * 0.22).foregroundStyle(Ink.red)
                Text(text).font(Face.text(20)).foregroundStyle(Ink.white.opacity(0.9))
            }
        }
        .fixedSize()
        .padding(.trailing, 22)
        .padding(.vertical, 10)
        .background(LinearGradient(colors: [Ink.red.opacity(0.22), Ink.red.opacity(0.02)], startPoint: .leading, endPoint: .trailing))
    }

    /// Now and then a scan down the entry or a glitch of the hologram, in turn; none unless
    /// *active*, and none left playing when the loop is cancelled.
    private func pulses(_ active: Bool) async {
        defer { pulse = nil }
        guard active else { return }
        var kind = Pulse.Kind.scan
        do {
            while true {
                try await Task.sleep(for: .seconds(Double.random(in: 10...16)))
                pulse = Pulse(kind: kind, start: .now)
                try await Task.sleep(for: .seconds(kind.duration))
                pulse = nil
                kind = kind == .scan ? .glitch : .scan
            }
        } catch {}
    }

    // MARK: The screen

    private func screen(t: Double, pulse: Pulse.State?) -> some View {
        let narration = Uplink.narration(words: words.count)
        let read = (t - Boot.narrationAt) / narration
        return VStack(alignment: .leading, spacing: 0) {
            Header(snapshot: snapshot, now: now, t: t)
                .frame(height: 96)
            HStack(alignment: .top, spacing: 40) {
                Intel(snapshot: snapshot, now: now, t: t)
                    .frame(width: 456)
                VStack(spacing: 0) {
                    Hologram(snapshot: snapshot, now: now, t: t, glitch: pulse?.kind == .glitch ? pulse?.progress : nil)
                        .frame(height: 248)
                    OrbitPlate(snapshot: snapshot, now: now, t: t)
                        .frame(height: 432)
                    Transmission(quote: snapshot.quote ?? snapshot.moon?.quote, words: words, read: read, t: t)
                        .frame(maxHeight: .infinity)
                }
                .frame(width: 808)
                Entry(snapshot: snapshot, now: now, t: t, scan: pulse?.kind == .scan ? pulse?.progress : nil)
                    .frame(width: 456)
            }
            .padding(.top, 22)
            .frame(height: 864, alignment: .top)
            Spacer(minLength: 0)
            StatBar(snapshot: snapshot, now: now)
                .appear(t, at: 1.1)
        }
        .padding(.horizontal, 64)
        .padding(.top, 26)
    }
}

// MARK: - The boot and the pulses

/// Where the terminal's boot is: dark before it, booting from a moment for a length, done.
private enum Boot: Equatable {
    case dark, booting(Date, length: Double), done

    /// When the narrator starts on the quote.
    static let narrationAt = 1.7

    var isBooting: Bool {
        if case .booting = self { true } else { false }
    }

    /// Seconds since the boot began: before everything when dark, after it all when done.
    func elapsed(at date: Date) -> Double {
        switch self {
        case .dark: -1
        case .booting(let start, _): date.timeIntervalSince(start)
        case .done: .infinity
        }
    }
}

/// A settled screen's occasional life: a scan down the entry or a glitch of the hologram.
private struct Pulse: Equatable {
    enum Kind { case scan, glitch
        var duration: Double { self == .scan ? 1.1 : 0.22 }
    }

    struct State {
        let kind: Kind
        /// 0 to 1 through it.
        let progress: Double
    }

    let kind: Kind
    let start: Date

    func at(_ date: Date) -> State? {
        let p = date.timeIntervalSince(start) / kind.duration
        return (0...1).contains(p) ? State(kind: kind, progress: p) : nil
    }
}

extension View {
    /// Fades and rises in from *at*, as the Codex's parts settle.
    fileprivate func appear(_ t: Double, at: Double, rise: CGFloat = 14) -> some View {
        let p = min(max((t - at) / 0.45, 0), 1)
        let eased = 1 - pow(1 - p, 3)
        return opacity(eased).offset(y: (1 - eased) * rise)
    }

    /// Slides in from the left from *at*, as Deus Ex's tiles do.
    fileprivate func slide(_ t: Double, at: Double) -> some View {
        let p = min(max((t - at) / 0.35, 0), 1)
        let eased = 1 - pow(1 - p, 3)
        return opacity(eased).offset(x: (1 - eased) * -40)
    }

    /// Dark until *at*, then a stutter, as a hologram finding its feed.
    fileprivate func flicker(_ t: Double, at: Double) -> some View {
        let d = t - at
        let level: Double = d < 0 ? 0 : d < 0.05 ? 0.7 : d < 0.12 ? 0.1 : d < 0.16 ? 0.9 : d < 0.2 ? 0.3 : 1
        return opacity(level)
    }
}

/// A heading breaking out of hex from *at*, locked a little under a second later.
private func decrypted(_ text: String, t: Double, at: Double) -> String {
    let progress = (t - at) / 0.9
    if progress >= 1 { return text }
    return Cyberpunk.decrypt(text, progress: max(0, progress), seed: Cyberpunk.seed(text), frame: Int(max(0, t) * 18))
}

// MARK: - Inks, faces, shapes

private enum Ink {
    // Deus Ex's gold.
    static let gold = p3(0xDE, 0xB0, 0x47)
    static let goldHot = p3(0xF6, 0xD2, 0x72)
    // The Codex's hologram.
    static let deep = rgb(0x02, 0x07, 0x0E)
    static let navy = rgb(0x05, 0x12, 0x20)
    static let panel = rgb(0x06, 0x16, 0x26)
    static let blue = p3(0x7F, 0xC4, 0xF0)
    static let blueHot = p3(0xDD, 0xF4, 0xFF)
    static let white = rgb(0xE4, 0xEE, 0xF5)
    static let muted = rgb(0x6E, 0x8D, 0xA6)
    static let dim = rgb(0x34, 0x50, 0x6A)
    // Deus Ex's slab.
    static let slabTop = rgb(0x6C, 0x71, 0x75)
    static let slabBottom = rgb(0x4C, 0x51, 0x55)
    static let well = rgb(0x04, 0x08, 0x0D)
    // Cyberpunk's red, for what is urgent.
    static let red = p3(0xFF, 0x5E, 0x55)

    static func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    /// A hero ink, in Display P3 (`WideColour.swift`).
    static func p3(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color.p3(Double(r) / 255, Double(g) / 255, Double(b) / 255)
    }

    /// The air: the hologram's blue while good, gold in moderate, red beyond.
    static func air(_ band: AirQuality.Band) -> Color {
        switch band {
        case .good: blue
        case .moderate: gold
        default: red
        }
    }
}

private enum Face {
    /// Deus Ex's wide face, for headings and the clock.
    static func wide(_ size: CGFloat) -> Font { .custom("Michroma-Regular", size: size) }

    /// The Codex's Saira, condensed for the interface.
    static func cond(_ size: CGFloat, _ weight: CGFloat = 500) -> Font { saira(size, weight: weight, width: 72) }

    /// Saira at its full width, for reading.
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

/// Interface caps in condensed Saira, tracked as the Codex sets them.
private struct Caps: View {
    let text: String
    var size: CGFloat
    var weight: CGFloat = 600
    var colour = Ink.muted
    var tracking: CGFloat = 0.2

    var body: some View {
        Text(text.uppercased())
            .font(Face.cond(size, weight))
            .tracking(size * tracking)
            .foregroundStyle(colour)
            .lineLimit(1)
    }
}

/// A rect with its bottom-right corner cut at 45°, Cyberpunk's panel shape.
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

/// Brackets at a rect's four corners, as the Codex and Deus Ex frame their panes.
private struct Brackets: Shape {
    var length: CGFloat = 16

    func path(in r: CGRect) -> Path {
        var p = Path()
        for (c, dx, dy) in [(CGPoint(x: r.minX, y: r.minY), 1.0, 1.0), (CGPoint(x: r.maxX, y: r.minY), -1.0, 1.0),
                            (CGPoint(x: r.minX, y: r.maxY), 1.0, -1.0), (CGPoint(x: r.maxX, y: r.maxY), -1.0, -1.0)] {
            p.move(to: CGPoint(x: c.x + length * dx, y: c.y))
            p.addLine(to: c)
            p.addLine(to: CGPoint(x: c.x, y: c.y + length * dy))
        }
        return p
    }
}

/// A section's label: a gold run and its name, as the panes are headed.
private struct SectionLabel: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Ink.gold).frame(width: 22, height: 3)
            Caps(text: title, size: 19, colour: Ink.white.opacity(0.85))
            Spacer(minLength: 0)
            if let detail { Caps(text: detail, size: 16, weight: 500, colour: Ink.muted) }
        }
    }
}

/// "9:30 AM" or "21:30", in the zone.
private func clock(_ date: Date, _ zone: TimeZone) -> String {
    let p = ClockTime.parts(date, in: zone)
    return p.period.map { "\(p.time) \($0)" } ?? p.time
}

// MARK: - The ground

/// The Codex's navy with its haze and scanlines, Deus Ex's faint shards of glass in gold, the
/// galaxy map's rings behind the orbit, and a vignette. Still, behind the drifting plate.
private struct Ground: View {
    var body: some View {
        Canvas { gc, size in
            let r = CGRect(origin: .zero, size: size)
            let u = size.height / 1080
            gc.fill(Path(r), with: .linearGradient(Gradient(colors: [Ink.navy, Ink.deep]),
                                                   startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            gc.fill(Path(r), with: .radialGradient(Gradient(colors: [Ink.blue.opacity(0.12), Ink.blue.opacity(0.03), .clear]),
                                                   center: CGPoint(x: size.width * 0.5, y: size.height * 0.25),
                                                   startRadius: 0, endRadius: size.width * 0.45))
            gc.fill(Path(r), with: .radialGradient(Gradient(colors: [Ink.gold.opacity(0.07), .clear]),
                                                   center: CGPoint(x: size.width * 0.5, y: size.height * 0.62),
                                                   startRadius: 0, endRadius: size.width * 0.3))
            var rng = SplitMix(seed: 0xDE05_C0DE)
            gc.drawLayer { l in
                l.addFilter(.blur(radius: 2 * u))
                for k in 0..<26 {
                    let c = CGPoint(x: rng.unit() * size.width, y: rng.unit() * size.height)
                    let radius = (40 + rng.unit() * 150) * u
                    let a0 = rng.unit() * 2 * .pi
                    var shard = Path()
                    for j in 0..<3 {
                        let a = a0 + Double(j) * (2 * .pi / 3) + (rng.unit() - 0.5) * 1.1
                        let p = CGPoint(x: c.x + cos(a) * radius * (0.5 + rng.unit()),
                                        y: c.y + sin(a) * radius * (0.35 + rng.unit() * 0.6))
                        j == 0 ? shard.move(to: p) : shard.addLine(to: p)
                    }
                    shard.closeSubpath()
                    l.fill(shard, with: .color((k % 3 == 0 ? Ink.gold : Ink.blue).opacity(0.02 + 0.025 * rng.unit())))
                    l.stroke(shard, with: .color(.white.opacity(0.03)), lineWidth: u)
                }
            }
            let c = CGPoint(x: size.width / 2, y: size.height * 0.6)
            for (k, radius) in [480.0, 640, 820].enumerated() {
                let rx = radius * u, ry = radius * 0.36 * u
                gc.stroke(Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: 2 * rx, height: 2 * ry)),
                          with: .color(Ink.blue.opacity(0.06 - Double(k) * 0.015)), lineWidth: 1.4 * u)
            }
            var scan = Path()
            let step = max(3, size.height / 360)
            var y: CGFloat = 0
            while y < size.height {
                scan.addRect(CGRect(x: 0, y: y, width: size.width, height: step * 0.3))
                y += step
            }
            gc.fill(scan, with: .color(.black.opacity(0.18)))
            gc.fill(Path(r), with: .radialGradient(Gradient(colors: [.clear, Ink.deep.opacity(0.85)]),
                                                   center: CGPoint(x: size.width / 2, y: size.height / 2),
                                                   startRadius: size.height * 0.55, endRadius: max(size.width, size.height) * 0.68))
        }
        .background(Ink.deep)
    }
}

// MARK: - The header

/// UPLINK in Deus Ex's wide gold, decrypting; the Codex's tabs; Deus Ex's icon tabs with their
/// diamond badges (today's events, the fortnight's birthdays, the weather's alerts); the date.
private struct Header: View {
    let snapshot: Snapshot
    let now: Date
    let t: Double

    var body: some View {
        let zone = snapshot.timeZone
        let today = Agenda.days(from: snapshot, now: now, count: 1)[0].events.count
        let birthdays = Cyberpunk.contacts(snapshot, now: now, limit: 9).count
        let alerts = snapshot.sources.weather?.data?.alerts.count ?? 0
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                Text(decrypted("UPLINK", t: t, at: 0.05))
                    .font(Face.wide(46))
                    .foregroundStyle(Ink.gold)
                    .shadow(color: Ink.gold.opacity(0.5), radius: 10)
                    .frame(width: 290, alignment: .leading)
                HStack(spacing: 34) {
                    tab("LOCAL", lit: true)
                    tab("ORBITAL", lit: false)
                }
                .appear(t, at: 0.3, rise: 0)
                Spacer(minLength: 0)
                HStack(spacing: 34) {
                    icon("calendar", badge: today > 0 ? "\(today)" : nil)
                    icon("gift", badge: birthdays > 0 ? "\(birthdays)" : nil)
                    icon("cloud.sun", badge: alerts > 0 ? "!" : nil, urgent: alerts > 0)
                    icon("dot.radiowaves.left.and.right", lit: true)
                }
                .appear(t, at: 0.35, rise: 0)
                Caps(text: now.formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated).day().month(.abbreviated)),
                     size: 24, colour: Ink.blue, tracking: 0.2)
                    .padding(.leading, 44)
                    .appear(t, at: 0.4, rise: 0)
            }
            .frame(height: 80)
            ZStack(alignment: .leading) {
                Rectangle().fill(.white.opacity(0.13)).frame(height: 1.2)
                Rectangle().fill(Ink.gold).frame(width: 220, height: 3)
                    .shadow(color: Ink.gold.opacity(0.7), radius: 6)
                    .scaleEffect(x: min(max(t / 0.5, 0.001), 1), anchor: .leading)
            }
            .padding(.horizontal, -64)
            .padding(.leading, 64)
        }
    }

    private func tab(_ name: String, lit: Bool) -> some View {
        VStack(spacing: 6) {
            Caps(text: name, size: 22, colour: lit ? Ink.white : Ink.muted)
            Rectangle().fill(lit ? Ink.blue : .clear).frame(height: 2.5)
        }
        .fixedSize()
        .padding(.top, 8)
    }

    private func icon(_ symbol: String, badge: String? = nil, lit: Bool = false, urgent: Bool = false) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 30, weight: .regular))
            .foregroundStyle(lit ? Ink.goldHot : Ink.white.opacity(0.72))
            .frame(width: 58, height: 58)
            // A view, not a style: a style background runs out into the safe area.
            .background { if lit { Rectangle().fill(Ink.gold.opacity(0.16)) } }
            .overlay(alignment: .bottom) {
                if let badge {
                    Text(badge)
                        .font(Face.cond(15, 800))
                        .foregroundStyle(.black.opacity(0.85))
                        .frame(width: 24, height: 24)
                        .background(Rectangle().fill(urgent ? Ink.red : Ink.gold).rotationEffect(.degrees(45)).frame(width: 18, height: 18))
                        .offset(y: 20)
                }
            }
    }
}

// MARK: - The intel

/// The agenda as Deus Ex's tiles: the next job lifted onto the slab, the rest in the well,
/// then the fortnight's birthdays; each tile's corner cut as Cyberpunk's are.
private struct Intel: View {
    let snapshot: Snapshot
    let now: Date
    let t: Double

    private static let tileHeight: CGFloat = 86
    private static let gap: CGFloat = 12

    var body: some View {
        let zone = snapshot.timeZone
        let room = Int((838 - 40 + Self.gap) / (Self.tileHeight + Self.gap))
        let contacts = Cyberpunk.contacts(snapshot, now: now, limit: 2)
        let jobs = Cyberpunk.jobs(snapshot, now: now, limit: max(1, room - contacts.count))
        let lifted = jobs.firstIndex { $0.state == .active || $0.state == .tracked }
        var tiles: [TileModel] = jobs.enumerated().map { i, job in
            TileModel(job: job, lifted: i == lifted, now: now, zone: zone)
        }
        tiles += contacts.prefix(max(0, room - tiles.count)).map { TileModel(birthday: $0, now: now, zone: zone) }
        return VStack(alignment: .leading, spacing: Self.gap) {
            SectionLabel(title: "INTEL // AGENDA", detail: "\(jobs.count) ACTIVE")
                .frame(height: 28)
                .appear(t, at: 0.3, rise: 0)
            if tiles.isEmpty {
                Tile(model: TileModel(title: "NO ENTRIES", caption: "Nothing on the calendar", symbol: "tray"))
                    .slide(t, at: 0.4)
            }
            ForEach(Array(tiles.enumerated()), id: \.offset) { i, tile in
                Tile(model: tile)
                    .frame(height: Self.tileHeight)
                    .slide(t, at: 0.4 + Double(i) * 0.07)
            }
        }
    }
}

private struct TileModel {
    var title: String
    var caption: String
    var symbol: String
    var captionColour = Ink.muted
    var lifted = false
    var urgent = false

    init(title: String, caption: String, symbol: String) {
        self.title = title
        self.caption = caption
        self.symbol = symbol
    }

    init(job: Cyberpunk.Job, lifted: Bool, now: Date, zone: TimeZone) {
        let e = job.event
        let place = e.shortLocation.map { " · " + $0 } ?? ""
        title = e.summary
        symbol = "calendar"
        self.lifted = lifted
        switch job.state {
        case .active:
            caption = "Under way · until \(clock(e.end, zone))" + place
            captionColour = Ink.red
            urgent = true
            symbol = "bolt.horizontal"
        case .tracked:
            let minutes = Int((e.start.timeIntervalSince(now) / 60).rounded(.up))
            let tomorrow = CivilDate(e.start, in: zone) != CivilDate(now, in: zone)
            caption = (minutes < 60 ? "In \(minutes) min" : (tomorrow ? "Tomorrow " : "") + clock(e.start, zone)) + place
            captionColour = Ink.goldHot
            symbol = "scope"
        case .upcoming:
            caption = clock(e.start, zone) + place
        case .tomorrow:
            caption = "Tomorrow " + clock(e.start, zone) + place
            captionColour = Ink.dim
        case .allDay:
            caption = "All day" + place
            captionColour = Ink.gold.opacity(0.8)
            symbol = "sun.max"
        }
    }

    init(birthday: Birthday, now: Date, zone: TimeZone) {
        let today = CivilDate(now, in: zone)
        let when = birthday.date == today ? "Today"
            : birthday.date == today.adding(days: 1) ? "Tomorrow"
            : birthday.date.start(in: zone).formatted(Date.FormatStyle(timeZone: zone).weekday(.wide))
        title = birthday.name
        caption = "Birthday · \(when)" + (birthday.age.map { " · turns \($0)" } ?? "")
        captionColour = birthday.date == today ? Ink.goldHot : Ink.blue
        symbol = "gift"
        lifted = birthday.date == today
    }
}

/// One tile: the slab when lifted (stepped out, with the white marker beside it), the dark
/// well otherwise.
private struct Tile: View {
    let model: TileModel

    var body: some View {
        let shape = Bevelled(cut: 16)
        HStack(spacing: 0) {
            Rectangle().fill(model.urgent ? Ink.red : model.lifted ? Ink.white.opacity(0.9) : .white.opacity(0.11))
                .frame(width: 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.title)
                    .font(Face.cond(27, 700))
                    .tracking(27 * 0.02)
                    .foregroundStyle(Ink.white)
                    .lineLimit(1)
                Text(model.caption)
                    .font(Face.text(19, 500))
                    .foregroundStyle(model.lifted ? (model.urgent ? Ink.red : Ink.white.opacity(0.85)) : model.captionColour)
                    .lineLimit(1)
            }
            .padding(.leading, 20)
            Spacer(minLength: 10)
            Image(systemName: model.symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(model.lifted ? Ink.white.opacity(0.92) : Ink.white.opacity(0.5))
                .frame(width: 70)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if model.lifted {
                shape.fill(LinearGradient(colors: [Ink.slabTop, Ink.slabBottom], startPoint: .top, endPoint: .bottom))
                    .overlay(shape.stroke(.white.opacity(0.2), lineWidth: 1.2))
                    .shadow(color: .black.opacity(0.6), radius: 10, y: 4)
            } else {
                shape.fill(Ink.well.opacity(0.82))
                    .overlay(shape.stroke(.white.opacity(0.06), lineWidth: 1.2))
            }
        }
        .offset(x: model.lifted ? 12 : 0)
        .overlay(alignment: .leading) {
            if model.lifted {
                Triangle().fill(Ink.white).frame(width: 10, height: 16).offset(x: -10)
            }
        }
    }
}

private struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.closeSubpath()
        return p
    }
}

// MARK: - The hologram

/// The clock as a hologram over the orbit's emitter: gold in Deus Ex's wide face with a bloom,
/// the date and place under it, the projector's beam behind. A glitch splits it red and blue
/// and slips it sideways.
private struct Hologram: View {
    let snapshot: Snapshot
    let now: Date
    let t: Double
    /// How far through a glitch, or nil.
    let glitch: Double?

    var body: some View {
        let zone = snapshot.timeZone
        let parts = ClockTime.parts(now, in: zone)
        let date = now.formatted(Date.FormatStyle(timeZone: zone).weekday(.wide).day().month(.wide))
        let place = snapshot.sources.weather?.data?.locationName
        let slip: CGFloat = glitch.map { $0 < 0.3 ? 14 : $0 < 0.6 ? -8 : 3 } ?? 0
        ZStack {
            Beam()
                .fill(LinearGradient(colors: [Ink.gold.opacity(0), Ink.gold.opacity(0.10)], startPoint: .top, endPoint: .bottom))
                .appear(t, at: 0.8, rise: 0)
            VStack(spacing: 10) {
                ZStack {
                    if glitch != nil {
                        face(parts, Ink.red).offset(x: -slip - 6).opacity(0.7).blendMode(.screen)
                        face(parts, Ink.blue).offset(x: slip + 6).opacity(0.7).blendMode(.screen)
                    }
                    face(parts, Ink.goldHot)
                        .shadow(color: Ink.gold.opacity(0.8), radius: 22)
                        .offset(x: slip)
                }
                Caps(text: [date, place].compactMap { $0 }.joined(separator: "  //  "), size: 24, weight: 500,
                     colour: Ink.blue, tracking: 0.24)
            }
            .flicker(t, at: 0.95)
        }
    }

    private func face(_ parts: (time: String, period: String?), _ colour: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(parts.time).font(Face.wide(132)).monospacedDigit()
            if let period = parts.period { Text(period).font(Face.wide(34)) }
        }
        .foregroundStyle(colour)
    }
}

/// The projector's beam: narrow at the emitter below, wide where it meets the hologram.
private struct Beam: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX - r.width * 0.42, y: r.minY + r.height * 0.1))
        p.addLine(to: CGPoint(x: r.midX + r.width * 0.42, y: r.minY + r.height * 0.1))
        p.addLine(to: CGPoint(x: r.midX + 40, y: r.maxY + 180))
        p.addLine(to: CGPoint(x: r.midX - 40, y: r.maxY + 180))
        p.closeSubpath()
        return p
    }
}

// MARK: - The orbit

/// Today as an orbit at a tilt, turning so that now is at the front: the hours round the rim,
/// the daylight in gold, the calendar's nodes riding the inner track, labelled where they face
/// the screen. It spins into place as the terminal boots.
private struct OrbitPlate: View {
    let snapshot: Snapshot
    let now: Date
    let t: Double

    var body: some View {
        let p = min(max((t - 0.5) / 1.3, 0), 1)
        let eased = 1 - pow(1 - p, 3)
        Canvas { gc, size in
            paint(spin: 0.3 * (1 - eased), &gc, size)
        }
        .opacity(min(eased * 1.6, 1))
        .scaleEffect(0.82 + 0.18 * eased)
    }

    private func paint(spin: Double, _ gc: inout GraphicsContext, _ size: CGSize) {
        let zone = snapshot.timeZone
        let c = CGPoint(x: size.width / 2, y: size.height * 0.46)
        let rx = size.width * 0.47, ry = rx * 0.36
        func point(_ turn: Double, _ k: Double) -> CGPoint {
            let a = (turn + spin) * 2 * .pi
            return CGPoint(x: c.x + k * rx * sin(a), y: c.y + k * ry * cos(a))
        }
        /// 1 at the front, 0 at the back.
        func near(_ turn: Double) -> Double { (cos((turn + spin) * 2 * .pi) + 1) / 2 }
        func arc(_ from: Double, _ to: Double, _ k: Double, _ colour: Color, width: CGFloat, glow: Bool = false) {
            var u = from
            while u < to {
                let v = min(u + 0.004, to)
                var seg = Path()
                seg.move(to: point(u, k)); seg.addLine(to: point(v, k))
                let alpha = 0.25 + 0.75 * near((u + v) / 2)
                if glow {
                    gc.drawLayer { l in
                        l.addFilter(.blur(radius: 6))
                        l.stroke(seg, with: .color(colour.opacity(alpha * 0.7)), style: StrokeStyle(lineWidth: width * 2.2, lineCap: .round))
                    }
                }
                gc.stroke(seg, with: .color(colour.opacity(alpha)), style: StrokeStyle(lineWidth: width, lineCap: .round))
                u = v
            }
        }
        func raw(_ date: Date) -> Double { date.timeIntervalSince(now) / 86_400 }

        // The plate's rings and its glass.
        gc.fill(Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: 2 * rx, height: 2 * ry)),
                with: .radialGradient(Gradient(colors: [Ink.blue.opacity(0.10), Ink.blue.opacity(0.02)]),
                                      center: c, startRadius: 0, endRadius: rx))
        for k in [1.0, 0.8, 0.62, 0.36] {
            gc.stroke(Path(ellipseIn: CGRect(x: c.x - k * rx, y: c.y - k * ry, width: 2 * k * rx, height: 2 * k * ry)),
                      with: .color(Ink.blue.opacity(k == 1 ? 0.45 : 0.18)), lineWidth: k == 1 ? 1.6 : 1)
        }
        // The hours round the rim: a tick each, a label every third.
        let midnight = CivilDate(now, in: zone).start(in: zone)
        for h in -24..<48 {
            let at = midnight.addingTimeInterval(Double(h) * 3600)
            let u = raw(at)
            guard u >= -0.5, u < 0.5 else { continue }
            let major = ((h % 24) + 24) % 3 == 0
            let a = point(u, 1), b = point(u, major ? 1.07 : 1.035)
            var tick = Path()
            tick.move(to: a); tick.addLine(to: b)
            gc.stroke(tick, with: .color(Ink.blue.opacity(0.3 + 0.6 * near(u))), lineWidth: major ? 2 : 1.2)
            if major {
                let label = Self.hour(at, zone)
                let n = near(u)
                gc.draw(Text(label).font(Face.cond(15 + 5 * n, 600)).tracking(2).foregroundColor(Ink.muted.opacity(0.35 + 0.65 * n)),
                        at: point(u, 1.16), anchor: .center)
            }
        }
        // The daylight: a gold arc on the outer track from sunrise round to sunset, as times of
        // day, so it wraps past the back of the orbit as the day does.
        let suns = Skylight.sunTimes(snapshot, now: now)
        if let rise = suns.first(where: \.rise)?.time, let set = suns.first(where: { !$0.rise })?.time {
            let from = Uplink.turn(rise, now: now)
            var to = Uplink.turn(set, now: now)
            if to <= from { to += 1 }
            arc(from, to, 0.9, Ink.gold, width: 5, glow: true)
            for (time, isRise) in [(rise, true), (set, false)] {
                let u = Uplink.turn(time, now: now), n = near(u)
                let at = point(u, 0.9)
                gc.fill(Path(ellipseIn: CGRect(x: at.x - 6, y: at.y - 6, width: 12, height: 12)),
                        with: .color(Ink.goldHot.opacity(0.4 + 0.6 * n)))
                // Inside the track, clear of the arc and the rim's hours.
                let inward = CGPoint(x: at.x + (c.x - at.x) * 0.1, y: at.y + (c.y - at.y) * 0.2)
                gc.draw(Text("\(isRise ? "RISE" : "SET") \(clock(time, zone))").font(Face.cond(16, 600)).tracking(2)
                            .foregroundColor(Ink.gold.opacity(0.4 + 0.6 * n)),
                        at: inward, anchor: at.x >= c.x ? .trailing : .leading)
            }
        }
        // The calendar's nodes on the inner track, labelled where they face the screen.
        let nodes = Uplink.nodes(snapshot, now: now)
        let tracked = nodes.first { !$0.isActive }
        var lastLabel = -1.0
        for node in nodes.reversed() {
            let colour = node.isActive ? Ink.red : node == tracked ? Ink.goldHot : Ink.blue
            arc(node.start, max(node.end, node.start + 0.004), 0.62, colour, width: 6, glow: node.isActive || node == tracked)
        }
        for node in nodes {
            let colour = node.isActive ? Ink.red : node == tracked ? Ink.goldHot : Ink.blueHot
            let at = point(node.start, 0.62), n = near(node.start)
            var diamond = Path()
            let s = 7 + 4 * n
            diamond.move(to: CGPoint(x: at.x, y: at.y - s)); diamond.addLine(to: CGPoint(x: at.x + s, y: at.y))
            diamond.addLine(to: CGPoint(x: at.x, y: at.y + s)); diamond.addLine(to: CGPoint(x: at.x - s, y: at.y)); diamond.closeSubpath()
            gc.fill(diamond, with: .color(colour.opacity(0.4 + 0.6 * n)))
            guard abs(node.start) < 0.3, node.start - lastLabel > 0.035 else { continue }
            lastLabel = node.start
            let name = node.event.summary.count > 22 ? String(node.event.summary.prefix(21)) + "…" : node.event.summary
            let when = node.isActive ? "NOW" : clock(node.event.start, zone)
            let label = Text(when + "  ").font(Face.cond(17, 700)).foregroundColor(colour)
                + Text(name).font(Face.cond(19, 500)).foregroundColor(Ink.white.opacity(0.95))
            // Inside the track, towards the centre, so the labels never cross the rim's hours.
            let inward = CGPoint(x: at.x + (c.x - at.x) * 0.16, y: at.y + (c.y - at.y) * 0.32 - 4)
            gc.draw(label, at: inward, anchor: node.start >= 0 ? .trailing : .leading)
        }
        // Now, at the front: a gold chevron on the rim, and the emitter at the centre.
        let front = point(-spin, 1)
        var chevron = Path()
        chevron.move(to: CGPoint(x: front.x - 14, y: front.y + 22)); chevron.addLine(to: CGPoint(x: front.x, y: front.y + 4))
        chevron.addLine(to: CGPoint(x: front.x + 14, y: front.y + 22)); chevron.closeSubpath()
        gc.fill(chevron, with: .color(Ink.goldHot))
        gc.draw(Text("NOW").font(Face.cond(18, 700)).tracking(5).foregroundColor(Ink.goldHot),
                at: CGPoint(x: front.x, y: front.y + 28), anchor: .top)
        gc.drawLayer { l in
            l.addFilter(.blur(radius: 10))
            l.fill(Path(ellipseIn: CGRect(x: c.x - 60, y: c.y - 18, width: 120, height: 36)), with: .color(Ink.gold.opacity(0.6)))
        }
        gc.stroke(Path(ellipseIn: CGRect(x: c.x - 34, y: c.y - 11, width: 68, height: 22)), with: .color(Ink.goldHot), lineWidth: 2)
    }

    /// "6 AM" or "06:00".
    private static func hour(_ date: Date, _ zone: TimeZone) -> String {
        let p = ClockTime.parts(date, in: zone)
        guard let period = p.period else { return p.time }
        return "\(p.time.split(separator: ":").first ?? "") \(period)"
    }
}

// MARK: - The transmission

/// The day's quote read aloud, as the Codex reads its entries: the narration bar with its voice
/// trace and progress, and the words lighting as the narrator reaches them.
private struct Transmission: View {
    let quote: Quote?
    let words: [String]
    /// How far through the reading, 0 to 1 (beyond 1 once read).
    let read: Double
    let t: Double

    var body: some View {
        let spoken = Uplink.spoken(words: words.count, progress: read)
        let speaking = read > 0 && read < 1
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Triangle().fill(Ink.blue).frame(width: 14, height: 18)
                Caps(text: "TRANSMISSION", size: 17, colour: Ink.muted)
                Voice(seed: Cyberpunk.seed(quote?.text ?? ""), take: speaking ? Int(t * 8) % 2 : -1)
                    .frame(width: 300, height: 30)
                ZStack(alignment: .leading) {
                    Rectangle().fill(Ink.blue.opacity(0.15))
                    Rectangle().fill(Ink.blue).scaleEffect(x: min(max(read, 0), 1), anchor: .leading)
                }
                .frame(height: 3)
            }
            if let quote {
                (Text(words.prefix(spoken).joined(separator: " ") + (spoken > 0 ? " " : ""))
                    .foregroundColor(Ink.white)
                    + Text(words.dropFirst(spoken).joined(separator: " "))
                    .foregroundColor(Ink.white.opacity(0.28)))
                    .font(Face.text(29))
                    .lineSpacing(4)
                    .minimumScaleFactor(0.6)
                    .shadow(color: Ink.blue.opacity(0.35), radius: 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Caps(text: "// " + decrypted(quote.author.uppercased(), t: t, at: 1.4), size: 20, colour: Ink.blue, tracking: 0.22)
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Bevelled(cut: 18).fill(Ink.panel.opacity(0.55)))
        .overlay(Brackets(length: 14).stroke(Ink.blue, lineWidth: 1.6))
        .appear(t, at: 1.3)
    }
}

/// The voice trace: bars about a centre line from the quote's seed, one of two takes while the
/// narrator speaks, flat in silence.
private struct Voice: View {
    let seed: UInt64
    /// 0 or 1 while speaking, -1 when silent.
    let take: Int

    var body: some View {
        Canvas { gc, size in
            var rng = SplitMix(seed: seed ^ (take == 1 ? 0x7A4E : 0x0C0D))
            let n = 48
            let step = size.width / CGFloat(n)
            var bars = Path()
            for k in 0..<n {
                let f = Double(k) / Double(n - 1)
                let envelope = 0.35 + 0.65 * sin(f * .pi)
                let v = take < 0 ? 0.08 : envelope * (0.15 + 0.85 * rng.unit())
                let h = max(1.5, CGFloat(v) * size.height)
                bars.addRect(CGRect(x: CGFloat(k) * step, y: size.height / 2 - h / 2, width: step * 0.55, height: h))
            }
            if take >= 0 {
                gc.drawLayer { l in
                    l.addFilter(.blur(radius: 3))
                    l.fill(bars, with: .color(Ink.blue.opacity(0.7)))
                }
            }
            gc.fill(bars, with: .color(take < 0 ? Ink.blue.opacity(0.45) : Ink.blueHot))
        }
    }
}

// MARK: - The entry

/// The weather as a Codex entry: its description decrypting, any alerts, the temperature, the
/// next 24 hours as a voice trace, then the readings and the outlook as chronology rows. Now
/// and then a gold scan runs down it.
private struct Entry: View {
    let snapshot: Snapshot
    let now: Date
    let t: Double
    /// How far through a scan, or nil.
    let scan: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let weather = snapshot.sources.weather?.data {
                content(weather)
            } else {
                Caps(text: "ENVIRONMENT", size: 19, colour: Ink.white.opacity(0.85))
                Text("No atmospheric feed")
                    .font(Face.cond(34, 600))
                    .foregroundStyle(Ink.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Ink.panel.opacity(0.72))
        .overlay(Rectangle().stroke(Ink.blue.opacity(0.2), lineWidth: 1))
        .overlay(Brackets(length: 18).stroke(Ink.gold, lineWidth: 2.2))
        .overlay {
            if let scan {
                GeometryReader { g in
                    let y = g.size.height * scan
                    LinearGradient(colors: [.clear, Ink.gold.opacity(0.1)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 120)
                        .overlay(alignment: .bottom) {
                            LinearGradient(colors: [.clear, Ink.gold, Ink.goldHot, Ink.gold, .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(height: 2.5)
                        }
                        .offset(y: y - 120)
                }
                .clipped()
            }
        }
        .appear(t, at: 0.55)
    }

    @ViewBuilder private func content(_ weather: Weather) -> some View {
        let zone = snapshot.timeZone
        SectionLabel(title: "ENVIRONMENT", detail: snapshot.sources.weather?.fetchedAt.map { "SYNC " + clock($0, zone) })
        Text(decrypted(weather.currentDescription.uppercased(), t: t, at: 0.75))
            .font(Face.cond(40, 600))
            .tracking(40 * 0.06)
            .foregroundStyle(Ink.white)
            .lineLimit(1)
            .fixedSize(horizontal: false, vertical: true)
        ForEach(weather.alerts.prefix(2), id: \.self) { alert in
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                Caps(text: alert.event, size: 19, weight: 700, colour: Ink.deep, tracking: 0.12)
            }
            .foregroundStyle(Ink.deep)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Bevelled(cut: 9).fill(Ink.red))
        }
        HStack(alignment: .center, spacing: 18) {
            Image(systemName: WeatherSymbol.name(for: weather.currentIcon))
                .font(.system(size: 58, weight: .light))
                .foregroundStyle(Ink.goldHot)
                .shadow(color: Ink.gold.opacity(0.6), radius: 10)
            // Michroma's degree sign is a full-size ring; Saira's sits as one should.
            (Text("\(Int(weather.currentTemp.rounded()))").font(Face.wide(56))
                + Text("°").font(Face.cond(56, 500)))
                .fixedSize()
                .foregroundStyle(Ink.white)
                .shadow(color: Ink.blue.opacity(0.5), radius: 12)
            VStack(alignment: .leading, spacing: 2) {
                Caps(text: "H \(deg(weather.high))  L \(deg(weather.low))", size: 20, colour: Ink.blue, tracking: 0.12)
                if let feels = weather.feelsLike {
                    Caps(text: "FEELS \(deg(feels))", size: 18, weight: 500, colour: Ink.muted, tracking: 0.12)
                }
            }
        }
        Forecast(samples: Uplink.trace(weather, now: now, count: 48), t: t)
            .frame(height: 62)
        Rectangle().fill(Ink.blue.opacity(0.25)).frame(height: 1)
        Chronology(title: "CONDITIONS", rows: readings(weather, zone: zone), t: t, at: 1.0)
        Chronology(title: "OUTLOOK", rows: outlook(weather, zone: zone), t: t, at: 1.25)
        Spacer(minLength: 0)
    }

    private func deg(_ v: Double) -> String { "\(Int(v.rounded()))°" }

    private func readings(_ w: Weather, zone: TimeZone) -> [Row] {
        var rows: [Row] = [Row(value: "\(w.humidity)%", label: "Humidity")]
        if let p = w.pressure { rows.append(Row(value: "\(Int(p.rounded()))", label: "Pressure, hPa")) }
        if let s = w.windSpeed {
            rows.append(Row(value: "\(Int(s.rounded())) \(w.windDeg.map { Compass.point($0) } ?? "")",
                            label: "Wind, \(snapshot.isMetric ? "m/s" : "mph")"))
        }
        if let uv = w.uvIndex {
            rows.append(Row(value: "\(Int(uv.rounded()))", label: "UV, " + Weatherglass.uvCategory(uv).lowercased(),
                            colour: uv >= 6 ? Ink.gold : nil))
        }
        if let air = snapshot.sources.airQuality?.data {
            rows.append(Row(value: "\(air.aqi)", label: "Air, " + air.shortLabel.lowercased(), colour: Ink.air(air.band)))
        }
        if let moon = snapshot.moon, let lit = moon.today?.illumination {
            rows.append(Row(value: "\(Int(lit.rounded()))%", label: moon.phaseName))
        }
        return rows
    }

    private func outlook(_ w: Weather, zone: TimeZone) -> [Row] {
        let today = CivilDate(now, in: zone)
        return Skylight.outlook(w, now: now, zone: zone, count: 5).map { day in
            let name = day.date == today ? "Today" : day.date.start(in: zone).formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated))
            let rain = (day.precipChance ?? 0) >= 0.1 ? " · rain \(Int(((day.precipChance ?? 0) * 100).rounded()))%" : ""
            return Row(value: name.uppercased(), label: "\(deg(day.high)) / \(deg(day.low))\(rain)",
                       symbol: WeatherSymbol.name(for: day.icon), selected: day.date == today)
        }
    }
}

/// The next 24 hours as a voice trace: a bar for each half hour about a centre line, as tall as
/// it is warm, brighter where rain is likely. It rises as the terminal boots.
private struct Forecast: View {
    let samples: [Uplink.Sample]
    let t: Double

    var body: some View {
        let grow = min(max((t - 0.9) / 0.7, 0), 1)
        VStack(spacing: 4) {
            Canvas { gc, size in
                guard samples.count > 1 else { return }
                let lo = samples.map(\.temp).min()!, hi = samples.map(\.temp).max()!
                let step = size.width / CGFloat(samples.count)
                var dry = Path(), wet = Path()
                for (k, s) in samples.enumerated() {
                    let f = hi > lo ? (s.temp - lo) / (hi - lo) : 0.5
                    let h = max(2, CGFloat(0.2 + 0.8 * f) * size.height * CGFloat(grow))
                    let r = CGRect(x: CGFloat(k) * step, y: size.height / 2 - h / 2, width: step * 0.55, height: h)
                    s.precip >= 0.3 ? wet.addRect(r) : dry.addRect(r)
                }
                gc.drawLayer { l in
                    l.addFilter(.blur(radius: 3))
                    l.fill(wet, with: .color(Ink.blueHot.opacity(0.7)))
                }
                gc.fill(dry, with: .color(Ink.blue.opacity(0.75)))
                gc.fill(wet, with: .color(Ink.blueHot))
            }
            HStack {
                Caps(text: "NOW", size: 14, colour: Ink.muted)
                Spacer()
                Caps(text: "NEXT 24 H  ·  TEMP / RAIN", size: 14, weight: 500, colour: Ink.dim)
                Spacer()
                Caps(text: "+24 H", size: 14, colour: Ink.muted)
            }
        }
    }
}

private struct Row {
    var value: String
    var label: String
    var colour: Color?
    var symbol: String?
    var selected = false
}

/// A Codex category open on its rows: the minus box and its name, then each row's value in the
/// hologram's blue and its label, the selected one on the Codex's lit bar.
private struct Chronology: View {
    let title: String
    let rows: [Row]
    let t: Double
    let at: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 12) {
                ZStack {
                    Rectangle().stroke(Ink.blue, lineWidth: 1.4).frame(width: 15, height: 15)
                    Rectangle().fill(Ink.blue).frame(width: 7, height: 1.6)
                }
                Caps(text: title, size: 19, colour: Ink.white)
            }
            .frame(height: 30)
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                HStack(spacing: 14) {
                    Text(row.value)
                        .font(Face.cond(21, 600))
                        .foregroundStyle(row.colour ?? (row.selected ? Ink.blueHot : Ink.blue))
                        .frame(width: 92, alignment: .leading)
                    if let symbol = row.symbol {
                        Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(Ink.muted).frame(width: 26)
                    }
                    Text(row.label)
                        .font(Face.text(20, row.selected ? 500 : 400))
                        .foregroundStyle(row.selected ? Ink.white : Ink.white.opacity(0.75))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 28)
                .frame(height: 29)
                .background {
                    if row.selected {
                        LinearGradient(colors: [Ink.blue.opacity(0.32), Ink.blue.opacity(0.06)], startPoint: .leading, endPoint: .trailing)
                            .overlay(alignment: .leading) { Rectangle().fill(Ink.blueHot).frame(width: 3) }
                    }
                }
                .appear(t, at: at + Double(i) * 0.04, rise: 6)
            }
        }
    }
}

// MARK: - The stat bar

/// Deus Ex's stat bar across the foot: the time, the next sunrise or sunset, the next job, the
/// uplink's signal on five slanted pips; the Codex's key hint at the right.
private struct StatBar: View {
    let snapshot: Snapshot
    let now: Date

    var body: some View {
        let zone = snapshot.timeZone
        let sun = Skylight.sunTimes(snapshot, now: now).first { $0.time > now }
        let next = Cyberpunk.jobs(snapshot, now: now, limit: 6).first { $0.state == .tracked || $0.state == .active }
        let pips = Uplink.signal(snapshot.sources)
        HStack(spacing: 40) {
            readout("TIME", clock(now, zone))
            if let sun { readout(sun.rise ? "SUNRISE" : "SUNSET", clock(sun.time, zone)) }
            if let next {
                readout(next.state == .active ? "UNDER WAY" : "NEXT", next.event.summary, urgent: next.state == .active)
            }
            HStack(spacing: 12) {
                readout("UPLINK", pips == 5 ? "STABLE" : pips >= 3 ? "WEAK" : "LOST", urgent: pips < 3)
                HStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { k in
                        Pip().fill(k < pips ? (pips < 3 ? Ink.red : Ink.gold) : .white.opacity(0.1)).frame(width: 18, height: 15)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Ink.blue, lineWidth: 2).frame(width: 26, height: 26)
                    Circle().fill(Ink.blue).frame(width: 10, height: 10)
                }
                Caps(text: "SETTINGS", size: 19, colour: Ink.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 64)
        .frame(height: 66)
        .background(.black.opacity(0.5))
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1.2) }
        .padding(.horizontal, -64)
    }

    private func readout(_ label: String, _ value: String, urgent: Bool = false) -> some View {
        HStack(spacing: 10) {
            Caps(text: label, size: 19, colour: Ink.white.opacity(0.82), tracking: 0.08)
            Text(value)
                .font(Face.cond(21, 600))
                .foregroundStyle(urgent ? Ink.red : Ink.gold)
                .lineLimit(1)
        }
        .fixedSize()
    }
}

/// A slanted pip of Deus Ex's gauge.
private struct Pip: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.3, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.3, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}
