import DashboardCore
import SwiftUI

/// A layout of the TV's own: everything the Pi sends, set as an adventurer's grimoire after the
/// quest logs and spellbooks of *Warcraft* and the tabletop. Goodmountain (Hermann S Designs'
/// Warcraft-inspired display serif) in gold for the headings, the clock and the figures;
/// Cormorant Garamond for the hand; Cinzel for the small capitals; all on dark parchment bound
/// in leather, with a gilt frame round the screen.
///
/// Across the top, the hour in gold over the watch it falls in ("Dusk", "The Witching Hour")
/// and the chronicler's date, with the realm (the weather's place) and the year at the right.
/// Down the left, the calendar as the quest log (the quest under way crossed with swords, the
/// next one marked with the gold exclamation, dailies with a scroll) and the month's birthdays
/// as feast days under a crown. In the middle, the augury: the sky painted as an illuminated
/// miniature beside the temperature, any alerts as omens under a skull, the readings as runes
/// over their bars, the next day as the tide of the hours, and the days to come as five small
/// miniatures. On the right, the moon in a gold ring with its phase and next turning, the day's
/// quote as the words of the sage, and the air as the dragon's breath. Along the foot, a candle
/// for each source, lit while its data is fresh, guttering as it ages, out once stale.
///
/// The page inks in as it appears: each panel rises in turn. Settled, the next quest's mark
/// breathes (not under Reduce Motion).
///
/// Drawn at 1920 x 1080 and scaled to the screen.
struct GrimoireView: Theme {
    let snapshot: Snapshot
    let now: Date

    static let fullBleed = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How far the page has inked in, 0 to 1.
    @State private var ink: Double = 0
    @State private var breathe = false

    private static let size = CGSize(width: 1920, height: 1080)

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / Self.size.width, geometry.size.height / Self.size.height)
            screen
                .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
                .scaleEffect(scale)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onBuildIn(reset: { settled in ink = settled ? 1 : 0 }) {
            withAnimation(.easeOut(duration: 1.6)) { ink = 1 }
        }
        .onAppear { breathe = !reduceMotion }
        .onChange(of: reduceMotion) { _, still in breathe = !still }
    }

    var backdrop: some View { Ground() }

    func notice(_ text: String) -> some View {
        HStack(spacing: 12) {
            Glyph("☠", size: 24, colour: Ink.gold)
            Text(text)
                .font(Face.caps(20, 600))
                .foregroundStyle(Ink.cream)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Ink.wax.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Ink.gold.opacity(0.7), lineWidth: 1.5))
    }

    // MARK: The page

    private var screen: some View {
        VStack(alignment: .leading, spacing: 0) {
            Header(snapshot: snapshot, now: now)
                .frame(height: Metrics.headerHeight)
                .opacity(ink)
            HStack(alignment: .top, spacing: Metrics.gutter) {
                QuestLog(snapshot: snapshot, now: now, breathe: breathe)
                    .frame(width: Metrics.leftWidth, height: Metrics.bodyHeight)
                    .rise(ink, index: 0)
                Augury(snapshot: snapshot, now: now)
                    .frame(width: Metrics.centreWidth, height: Metrics.bodyHeight)
                    .rise(ink, index: 1)
                VStack(spacing: Metrics.paneGap) {
                    if let moon = snapshot.moon {
                        Lunar(moon: moon, snapshot: snapshot, now: now)
                            .frame(height: 236)
                            .rise(ink, index: 2)
                    }
                    Sage(quote: snapshot.quote ?? snapshot.moon?.quote)
                        .frame(maxHeight: .infinity)
                        .rise(ink, index: 3)
                    if let air = snapshot.sources.airQuality?.data {
                        Breath(air: air)
                            .frame(height: 150)
                            .rise(ink, index: 4)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: Metrics.bodyHeight)
            }
            .padding(.top, 14)
            Spacer(minLength: 0)
            Candles(sources: snapshot.sources)
                .frame(height: 40)
                .rise(ink, index: 5)
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 36)
        .padding(.bottom, 30)
    }
}

// MARK: - Inks, faces, geometry

private enum Ink {
    /// The binding: dark leather.
    static let leather = rgb(0x14, 0x0D, 0x0A)
    static let leatherGlow = rgb(0x3D, 0x26, 0x16)
    /// The page.
    static let parchment = rgb(0x27, 0x1D, 0x15)
    static let parchmentDeep = rgb(0x1C, 0x14, 0x0E)
    static let gold = p3(0xD9, 0xB4, 0x5A)
    static let goldBright = p3(0xF6, 0xDE, 0x96)
    static let goldDim = p3(0x92, 0x74, 0x3A)
    static let goldDeep = rgb(0x5E, 0x47, 0x20)
    static let cream = rgb(0xEC, 0xE0, 0xC4)
    static let creamDim = rgb(0xB5, 0xA5, 0x86)
    static let ash = rgb(0x6E, 0x66, 0x5A)
    /// Omens and the notice: sealing wax.
    static let wax = rgb(0x5A, 0x1E, 0x1A)
    static let ember = p3(0xE0, 0x62, 0x4A)
    static let rain = p3(0x86, 0xAE, 0xD0)
    static let verdant = p3(0x9A, 0xC4, 0x7E)

    static func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    /// A hero ink, in Display P3 (`WideColour.swift`).
    static func p3(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color.p3(Double(r) / 255, Double(g) / 255, Double(b) / 255)
    }

    /// Gilt lettering: light at the top, deep at the foot.
    static let gilt = LinearGradient(colors: [goldBright, gold, goldDeep], startPoint: .top, endPoint: .bottom)

    /// The dragon's breath: verdant while sweet, gold while fair, ember beyond.
    static func breath(_ band: AirQuality.Band) -> Color {
        switch band {
        case .good: verdant
        case .moderate: gold
        default: ember
        }
    }
}

private enum Face {
    /// Goodmountain, for the headings, the hour and the figures; a display face, so never small.
    static func title(_ size: CGFloat) -> Font { .custom("Goodmountain-Regular", size: size) }
    /// Cormorant Garamond, the hand.
    static func hand(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font { .custom("Cormorant Garamond", size: size).weight(weight) }
    static func italic(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font { .custom("CormorantGaramond-LightItalic", size: size).weight(weight) }
    /// Cinzel, the small capitals.
    static func caps(_ size: CGFloat, _ weight: CGFloat = 500) -> Font { .custom("Cinzel", size: size).weight(Font.Weight(weight)) }
}

private extension Font.Weight {
    init(_ value: CGFloat) {
        switch value {
        case ..<450: self = .regular
        case ..<550: self = .medium
        case ..<650: self = .semibold
        default: self = .bold
        }
    }
}

private enum Metrics {
    static let margin: CGFloat = 56
    static let gutter: CGFloat = 26
    static let headerHeight: CGFloat = 128
    static let leftWidth: CGFloat = 560
    static let centreWidth: CGFloat = 700
    /// From under the header to over the candles.
    static let bodyHeight: CGFloat = 820
    static let paneGap: CGFloat = 16
}

/// Gilt lettering in Goodmountain, with the shadow that lifts it off the page.
private struct Gilt: View {
    let text: String
    let size: CGFloat
    var style: AnyShapeStyle = AnyShapeStyle(Ink.gilt)

    init(_ text: String, size: CGFloat) {
        self.text = text
        self.size = size
    }

    init(_ text: String, size: CGFloat, colour: Color) {
        self.text = text
        self.size = size
        self.style = AnyShapeStyle(colour)
    }

    var body: some View {
        Text(text)
            .font(Face.title(size))
            .foregroundStyle(style)
            .shadow(color: .black.opacity(0.75), radius: 1, y: max(1, size / 40))
            .lineLimit(1)
    }
}

/// One of Goodmountain's own glyphs (its Warcraft-inspired swords, scroll, crown, candle…),
/// set in a colour.
private struct Glyph: View {
    let glyph: String
    let size: CGFloat
    var colour: Color

    init(_ glyph: String, size: CGFloat, colour: Color = Ink.gold) {
        self.glyph = glyph
        self.size = size
        self.colour = colour
    }

    var body: some View {
        Text(glyph)
            .font(Face.title(size))
            .foregroundStyle(colour)
            .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
    }
}

/// Small capitals in Cinzel.
private struct Caps: View {
    let text: String
    var size: CGFloat
    var weight: CGFloat = 500
    var colour = Ink.goldDim
    var tracking: CGFloat = 0.1

    init(_ text: String, size: CGFloat, weight: CGFloat = 500, colour: Color = Ink.goldDim, tracking: CGFloat = 0.1) {
        self.text = text
        self.size = size
        self.weight = weight
        self.colour = colour
        self.tracking = tracking
    }

    var body: some View {
        Text(text.uppercased())
            .font(Face.caps(size, weight))
            .tracking(size * tracking)
            .foregroundStyle(colour)
            .lineLimit(1)
    }
}

/// A gold rule with a diamond at its *end* (or in its middle).
private struct Rule: View {
    enum Diamond { case leading, trailing, middle, none }
    var diamond = Diamond.middle
    var colour = Ink.gold

    var body: some View {
        Canvas { gc, size in
            let y = size.height / 2
            let d: CGFloat = 5
            let x: CGFloat? = switch diamond {
            case .leading: d
            case .trailing: size.width - d
            case .middle: size.width / 2
            case .none: nil
            }
            var line = Path()
            if let x {
                line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: x - d - 3, y: y))
                line.move(to: CGPoint(x: x + d + 3, y: y)); line.addLine(to: CGPoint(x: size.width, y: y))
                var gem = Path()
                gem.move(to: CGPoint(x: x, y: y - d)); gem.addLine(to: CGPoint(x: x + d, y: y))
                gem.addLine(to: CGPoint(x: x, y: y + d)); gem.addLine(to: CGPoint(x: x - d, y: y)); gem.closeSubpath()
                gc.fill(gem, with: .color(colour))
            } else {
                line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: size.width, y: y))
            }
            gc.stroke(line, with: .linearGradient(
                Gradient(colors: [colour.opacity(0.15), colour.opacity(0.8), colour.opacity(0.15)]),
                startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)), lineWidth: 1.2)
        }
        .frame(height: 12)
    }
}

/// A page of the tome: dark parchment in a gilt frame with corner-pieces, its title in gold
/// between two rules, a glyph before it.
private struct Panel<Content: View>: View {
    let title: String
    let glyph: String
    var note: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Rule(diamond: .leading)
                HStack(spacing: 12) {
                    Glyph(glyph, size: 28)
                    Gilt(title, size: 34)
                }
                .fixedSize()
                Rule(diamond: .trailing)
            }
            .overlay(alignment: .trailing) {
                if let note {
                    Caps(note, size: 13, colour: Ink.goldDim.opacity(0.9))
                        .padding(.horizontal, 8)
                        .background(Ink.parchment)
                        .offset(y: 20)
                }
            }
            .frame(height: 44)
            content
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
            shape.fill(LinearGradient(colors: [Ink.parchment, Ink.parchmentDeep], startPoint: .top, endPoint: .bottom))
                .overlay(shape.stroke(Ink.gold.opacity(0.55), lineWidth: 1.6))
                .overlay(shape.inset(by: 5).stroke(Ink.goldDeep.opacity(0.7), lineWidth: 1))
                .overlay(CornerPieces().stroke(Ink.gold.opacity(0.85), lineWidth: 1.6))
                .shadow(color: .black.opacity(0.5), radius: 14, y: 6)
        }
    }
}

/// The corner-pieces of a frame: a short bracket inside each corner, with a bead.
private struct CornerPieces: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let inset: CGFloat = 5, arm: CGFloat = 22, bead: CGFloat = 2.5
        for (sx, sy) in [(1.0, 1.0), (-1.0, 1.0), (1.0, -1.0), (-1.0, -1.0)] {
            let cx = sx > 0 ? r.minX + inset : r.maxX - inset
            let cy = sy > 0 ? r.minY + inset : r.maxY - inset
            p.move(to: CGPoint(x: cx + sx * arm, y: cy + sy * 9))
            p.addLine(to: CGPoint(x: cx + sx * 9, y: cy + sy * 9))
            p.addLine(to: CGPoint(x: cx + sx * 9, y: cy + sy * arm))
            let b = CGPoint(x: cx + sx * 14, y: cy + sy * 14)
            p.addEllipse(in: CGRect(x: b.x - bead, y: b.y - bead, width: bead * 2, height: bead * 2))
        }
        return p
    }
}

/// A rune's bar: a dark slot with a gold fill to *fraction*, a bead at its end.
private struct RuneBar: View {
    let fraction: Double
    var colour = Ink.gold

    var body: some View {
        GeometryReader { g in
            let w = g.size.width * min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.45))
                    .overlay(Capsule().stroke(Ink.goldDeep.opacity(0.6), lineWidth: 1))
                Capsule().fill(LinearGradient(colors: [colour.opacity(0.7), colour], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(w, 6))
                    .padding(1.5)
            }
        }
        .frame(height: 7)
    }
}

// MARK: - The binding

/// Dark leather with a warm glow behind the pages, a faint grain, a gilt frame inside the
/// screen's edge with fleurons at its corners, and a vignette. Still, behind the drifting page.
private struct Ground: View {
    var body: some View {
        Canvas { gc, size in
            let r = CGRect(origin: .zero, size: size)
            gc.fill(Path(r), with: .color(Ink.leather))
            gc.fill(Path(r), with: .radialGradient(
                Gradient(colors: [Ink.leatherGlow.opacity(0.85), Ink.leatherGlow.opacity(0.25), .clear]),
                center: CGPoint(x: size.width * 0.5, y: size.height * 0.45),
                startRadius: 0, endRadius: size.width * 0.62))
            // The grain: a scatter of darker flecks, the same each launch.
            var random = SplitMix(seed: 0x4C45_4154)  // "LEAT"
            var grain = Path()
            for _ in 0..<2400 {
                let p = CGPoint(x: random.unit() * size.width, y: random.unit() * size.height)
                let w = 1 + random.unit() * 3
                grain.addRect(CGRect(x: p.x, y: p.y, width: w, height: 1))
            }
            gc.fill(grain, with: .color(.black.opacity(0.35)))
            // The frame: a double gilt line, a fleuron in each corner.
            let unit = size.height / 1080
            let outer = r.insetBy(dx: 20 * unit, dy: 20 * unit)
            let inner = r.insetBy(dx: 28 * unit, dy: 28 * unit)
            gc.stroke(Path(outer), with: .color(Ink.gold.opacity(0.55)), lineWidth: 2 * unit)
            gc.stroke(Path(inner), with: .color(Ink.goldDeep.opacity(0.8)), lineWidth: 1 * unit)
            for (sx, sy) in [(1.0, 1.0), (-1.0, 1.0), (1.0, -1.0), (-1.0, -1.0)] {
                let cx = sx > 0 ? inner.minX : inner.maxX
                let cy = sy > 0 ? inner.minY : inner.maxY
                var fleuron = Path()
                let s = 26 * unit
                fleuron.move(to: CGPoint(x: cx, y: cy))
                fleuron.addQuadCurve(to: CGPoint(x: cx + sx * s, y: cy + sy * s * 0.35), control: CGPoint(x: cx + sx * s * 0.2, y: cy + sy * s * 0.7))
                fleuron.addQuadCurve(to: CGPoint(x: cx, y: cy), control: CGPoint(x: cx + sx * s * 0.7, y: cy + sy * s * 0.2))
                fleuron.move(to: CGPoint(x: cx, y: cy))
                fleuron.addQuadCurve(to: CGPoint(x: cx + sx * s * 0.35, y: cy + sy * s), control: CGPoint(x: cx + sx * s * 0.7, y: cy + sy * s * 0.2))
                fleuron.addQuadCurve(to: CGPoint(x: cx, y: cy), control: CGPoint(x: cx + sx * s * 0.2, y: cy + sy * s * 0.7))
                gc.fill(fleuron, with: .color(Ink.gold.opacity(0.8)))
                let d = 6 * unit
                let g = CGPoint(x: cx + sx * s * 0.95, y: cy + sy * s * 0.95)
                var gem = Path()
                gem.move(to: CGPoint(x: g.x, y: g.y - d)); gem.addLine(to: CGPoint(x: g.x + d, y: g.y))
                gem.addLine(to: CGPoint(x: g.x, y: g.y + d)); gem.addLine(to: CGPoint(x: g.x - d, y: g.y)); gem.closeSubpath()
                gc.fill(gem, with: .color(Ink.gold.opacity(0.8)))
            }
            gc.fill(Path(r), with: .radialGradient(
                Gradient(colors: [.clear, .black.opacity(0.55)]),
                center: CGPoint(x: size.width / 2, y: size.height / 2),
                startRadius: size.height * 0.45, endRadius: max(size.width, size.height) * 0.64))
        }
        .background(Ink.leather)
    }
}

// MARK: - The header

/// The hour in gold over its watch and the chronicler's date; the realm and the year at the right.
private struct Header: View {
    let snapshot: Snapshot
    let now: Date

    var body: some View {
        let zone = snapshot.timeZone
        let clock = ClockTime.parts(now, in: zone)
        let year = Self.year(now, in: zone)
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Gilt(clock.time, size: 118)
                    if let period = clock.period {
                        Caps(period, size: 30, weight: 600, colour: Ink.gold)
                    }
                    Text(Grimoire.watch(snapshot, now: now))
                        .font(Face.italic(40))
                        .foregroundStyle(Ink.cream)
                        .padding(.leading, 18)
                }
                .frame(height: 96, alignment: .bottom)
                Caps(Grimoire.dateLine(now, zone: zone), size: 22, colour: Ink.gold, tracking: 0.14)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Gilt(snapshot.sources.weather?.data?.locationName ?? "The Realm", size: 46)
                Caps("Anno \(roman(year))", size: 20, colour: Ink.goldDim, tracking: 0.16)
            }
        }
    }

    /// The year in the dashboard's zone, as the clock and the date beside it are.
    private static func year(_ now: Date, in zone: TimeZone) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.component(.year, from: now)
    }

    /// The year in Roman numerals, as the frontispiece has it.
    private func roman(_ n: Int) -> String {
        let table: [(Int, String)] = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
                                      (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var n = n, out = ""
        for (value, numeral) in table {
            while n >= value { out += numeral; n -= value }
        }
        return out
    }
}

// MARK: - The quest log

/// The calendar as quests, and the month's birthdays as feast days under them.
private struct QuestLog: View {
    let snapshot: Snapshot
    let now: Date
    let breathe: Bool

    private static let titleHeight: CGFloat = 44 + 12
    private static let chrome: CGFloat = 14 + 18
    private static let rowHeight: CGFloat = 74
    private static let rowGap: CGFloat = 6
    private static let feastHeading: CGFloat = 18 + 36 + 6
    private static let feastRow: CGFloat = 56

    var body: some View {
        let zone = snapshot.timeZone
        let feasts = Grimoire.feasts(snapshot, now: now, limit: 3)
        let feastsHeight = feasts.isEmpty ? 0 : Self.feastHeading + CGFloat(feasts.count) * (Self.feastRow + Self.rowGap)
        let room = Metrics.bodyHeight - Self.chrome - Self.titleHeight - feastsHeight
        let limit = max(1, Int((room + Self.rowGap) / (Self.rowHeight + Self.rowGap)))
        let quests = Grimoire.quests(snapshot, now: now, limit: limit)
        Panel(title: "Quests", glyph: "⚔", note: quests.isEmpty ? nil : "\(quests.count) in the log") {
            VStack(alignment: .leading, spacing: Self.rowGap) {
                if quests.isEmpty {
                    Empty(line: "The log lies empty.", sub: "Rest, adventurer: nothing is asked of you today.")
                        .frame(height: Self.rowHeight * 2)
                }
                ForEach(quests, id: \.self) { quest in
                    QuestRow(quest: quest, now: now, zone: zone, breathe: breathe)
                        .frame(height: Self.rowHeight)
                }
                if !feasts.isEmpty {
                    HStack(spacing: 12) {
                        Glyph("👑", size: 24)
                        Gilt("Feast Days", size: 28)
                        Rule(diamond: .trailing)
                    }
                    .frame(height: 36)
                    .padding(.top, 18)
                    .padding(.bottom, 6)
                    ForEach(feasts, id: \.self) { feast in
                        FeastRow(feast: feast, zone: zone)
                            .frame(height: Self.feastRow)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// A line for an empty page.
private struct Empty: View {
    let line: String
    let sub: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(line).font(Face.italic(32)).foregroundStyle(Ink.cream)
            Text(sub).font(Face.hand(22)).foregroundStyle(Ink.creamDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }
}

/// A calendar event as a quest: its mark at the left (the swords for one under way, the gold
/// exclamation for the next, a scroll for a daily), its name in the hand, and when and where.
private struct QuestRow: View {
    let quest: Grimoire.Quest
    let now: Date
    let zone: TimeZone
    let breathe: Bool

    var body: some View {
        let event = quest.event
        let lit = quest.state == .underway || quest.state == .next
        let place = event.shortLocation.map { " · " + $0 } ?? ""
        HStack(spacing: 0) {
            mark
                .frame(width: 58)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.summary)
                    .font(Face.hand(30, .semibold))
                    .foregroundStyle(quest.state == .tomorrow ? Ink.creamDim : Ink.cream)
                    .lineLimit(1)
                Caps(when + place, size: 15, colour: lit ? Ink.gold : Ink.goldDim, tracking: 0.08)
            }
            .padding(.leading, 10)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 8)
        .background {
            if lit {
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(colors: [Ink.gold.opacity(quest.state == .underway ? 0.26 : 0.16), Ink.gold.opacity(0)],
                                         startPoint: .leading, endPoint: .trailing))
                    .overlay(alignment: .leading) { Rectangle().fill(Ink.gold).frame(width: 3).padding(.vertical, 6) }
            }
        }
    }

    @ViewBuilder private var mark: some View {
        switch quest.state {
        case .underway:
            Glyph("⚔", size: 40, colour: Ink.goldBright)
                .shadow(color: Ink.gold.opacity(0.8), radius: 8)
        case .next:
            Glyph("!", size: 54, colour: Ink.goldBright)
                .shadow(color: Ink.gold.opacity(0.7), radius: 8)
                .scaleEffect(breathe ? 1.1 : 1)
                .animation(breathe ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true) : .default, value: breathe)
        case .today:
            Glyph("!", size: 54, colour: Ink.gold)
        case .tomorrow:
            Glyph("!", size: 54, colour: Ink.ash)
        case .daily:
            Glyph("📜", size: 36, colour: Ink.gold)
        }
    }

    /// "Under way until 6:30 PM", "Begins in 25 min", "Begins 5:30 PM", "On the morrow, 9:00 AM", "All day".
    private var when: String {
        let event = quest.event
        switch quest.state {
        case .underway: return "Under way until \(clock(event.end, zone))"
        case .next:
            let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
            if minutes < 60 { return "Begins in \(max(minutes, 1)) min" }
            return CivilDate(event.start, in: zone) == CivilDate(now, in: zone)
                ? "Begins \(clock(event.start, zone))" : "On the morrow, \(clock(event.start, zone))"
        case .today: return "Begins \(clock(event.start, zone))"
        case .tomorrow: return "On the morrow, \(clock(event.start, zone))"
        case .daily: return "All day"
        }
    }
}

/// A birthday as a feast day: whose, when, and the age they come to.
private struct FeastRow: View {
    let feast: Grimoire.Feast
    let zone: TimeZone

    var body: some View {
        let today = feast.daysAway == 0
        HStack(spacing: 0) {
            Glyph("👑", size: 30, colour: today ? Ink.goldBright : Ink.goldDim)
                .shadow(color: Ink.gold.opacity(today ? 0.8 : 0), radius: 8)
                .frame(width: 58)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(feast.birthday.name)’s name day")
                    .font(Face.hand(27, .semibold))
                    .foregroundStyle(Ink.cream)
                    .lineLimit(1)
                Caps(Grimoire.feastWhen(feast, zone: zone) + (feast.birthday.age.map { " · comes to \($0)" } ?? ""),
                     size: 14, colour: today ? Ink.gold : Ink.goldDim, tracking: 0.08)
            }
            .padding(.leading, 10)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - The augury

/// The weather: the sky as an illuminated miniature beside the temperature, omens, the runes,
/// the tide of the hours and the days to come.
private struct Augury: View {
    let snapshot: Snapshot
    let now: Date

    var body: some View {
        let zone = snapshot.timeZone
        let weather = snapshot.sources.weather?.data
        let read = snapshot.sources.weather?.fetchedAt.map { "Read at \(clock($0, zone))" }
        Panel(title: "The Augury", glyph: "💎", note: weather == nil ? nil : read) {
            if let weather {
                VStack(alignment: .leading, spacing: 10) {
                    Hero(snapshot: snapshot, weather: weather, now: now)
                        .frame(height: 206)
                    Rule(diamond: .middle, colour: Ink.goldDim)
                    Runes(snapshot: snapshot, weather: weather, now: now)
                        .frame(height: 136)
                    Subheading("The Tide of the Hours")
                    Tide(snapshot: snapshot, weather: weather, now: now)
                        .frame(height: 128)
                    Subheading("Days to Come")
                    Outlook(snapshot: snapshot, weather: weather, now: now)
                        .frame(maxHeight: .infinity)
                }
            } else {
                Empty(line: "The skies are veiled.", sub: "The augur has no reading of the weather.")
                    .frame(maxHeight: .infinity)
            }
        }
    }
}

/// A small heading within a page: capitals between two rules.
private struct Subheading: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(spacing: 12) {
            Rule(diamond: .none, colour: Ink.goldDim)
            Caps(text, size: 15, weight: 600, colour: Ink.gold, tracking: 0.18).fixedSize()
            Rule(diamond: .none, colour: Ink.goldDim)
        }
        .frame(height: 22)
    }
}

/// The sky now, painted, in a gilt frame; beside it the temperature in gold, the description in
/// the hand, the day's range, and any alerts as omens under a skull.
private struct Hero: View {
    let snapshot: Snapshot
    let weather: Weather
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            Miniature(icon: weather.currentIcon, moonFraction: Skylight.moon(snapshot, now: now)?.fraction ?? snapshot.moon?.today?.fraction,
                      size: CGSize(width: 290, height: 206))
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Gilt("\(Int(weather.currentTemp.rounded()))", size: 96)
                    Gilt("°", size: 60)
                    Spacer(minLength: 0)
                }
                .frame(height: 100, alignment: .bottom)
                Text(weather.currentDescription.prefix(1).uppercased() + weather.currentDescription.dropFirst())
                    .font(Face.italic(32))
                    .foregroundStyle(Ink.cream)
                    .lineLimit(1)
                HStack(spacing: 16) {
                    Caps("High \(degrees(weather.high))", size: 17, weight: 600, colour: Ink.gold)
                    Caps("Low \(degrees(weather.low))", size: 17, weight: 600, colour: Ink.gold)
                    if let feels = weather.feelsLike {
                        Caps("Feels \(degrees(feels))", size: 17, colour: Ink.goldDim)
                    }
                }
                .padding(.top, 4)
                if !weather.alerts.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(weather.alerts.prefix(2), id: \.self) { alert in
                            HStack(spacing: 8) {
                                Glyph("☠", size: 20, colour: Ink.goldBright)
                                Caps(alert.event, size: 15, weight: 600, colour: Ink.cream, tracking: 0.06)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Ink.wax))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Ink.ember.opacity(0.7), lineWidth: 1.2))
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func degrees(_ v: Double) -> String { "\(Int(v.rounded()))°" }
}

/// The weather painting in a gilt frame, as a manuscript's miniature.
private struct Miniature: View {
    let icon: String
    let moonFraction: Double?
    let size: CGSize

    var body: some View {
        WeatherArt(icon: icon, moonFraction: moonFraction, size: size, light: Ink.cream, accent: Ink.gold)
            .equatable()
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Ink.gold.opacity(0.8), lineWidth: 2))
            .overlay(RoundedRectangle(cornerRadius: 5).inset(by: 4).stroke(Ink.goldDeep.opacity(0.8), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
    }
}

/// The readings as runes: a name, a value and a bar each.
private struct Runes: View {
    let snapshot: Snapshot
    let weather: Weather
    let now: Date

    private struct Rune: Identifiable {
        let label: String
        let value: String
        let fraction: Double
        var colour = Ink.gold
        var id: String { label }
    }

    var body: some View {
        let runes = Array(self.runes.prefix(6))
        Grid(horizontalSpacing: 26, verticalSpacing: 10) {
            ForEach(0..<(runes.count + 2) / 3, id: \.self) { row in
                GridRow {
                    ForEach(runes[(row * 3)..<min(row * 3 + 3, runes.count)]) { rune in
                        VStack(alignment: .leading, spacing: 2) {
                            Caps(rune.label, size: 12, colour: Ink.goldDim, tracking: 0.14)
                            Text(rune.value)
                                .font(Face.hand(24, .semibold))
                                .foregroundStyle(Ink.cream)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            RuneBar(fraction: rune.fraction, colour: rune.colour)
                                .padding(.top, 3)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    /// Humidity, wind, pressure, UV, the chance of rain and the daylight: what the weather has.
    private var runes: [Rune] {
        let zone = snapshot.timeZone
        var out = [Rune(label: "Humidity", value: "\(weather.humidity)%", fraction: Double(weather.humidity) / 100)]
        if let speed = weather.windSpeed {
            let compass = weather.windDeg.map { Compass.point($0) + " " } ?? ""
            out.append(Rune(label: "Wind", value: "\(compass)\(Int(speed.rounded())) \(snapshot.isMetric ? "m/s" : "mph")",
                            fraction: speed / (snapshot.isMetric ? 15 : 35)))
        }
        if let p = weather.pressure {
            out.append(Rune(label: "Pressure", value: "\(Int(p.rounded())) hPa", fraction: Cyberpunk.fraction(p, low: 970, high: 1050)))
        }
        if let uv = weather.uvIndex {
            out.append(Rune(label: "Sun's Wrath", value: "\(Int(uv.rounded())) \(Weatherglass.uvCategory(uv).capitalized)",
                            fraction: uv / 11, colour: uv >= 6 ? Ink.ember : Ink.gold))
        }
        // The nearest hourly slot's chance; without one (an older cache keeps no hourly grid),
        // today's from the daily forecast. The ribbon's "now" point would read 0% either way.
        let slot = weather.hourly.min { abs($0.time.timeIntervalSince(now)) < abs($1.time.timeIntervalSince(now)) }
        let rain = slot?.precipChance
            ?? Skylight.outlook(weather, now: now, zone: zone, count: 1).first?.precipChance
        if let rain {
            out.append(Rune(label: "Chance of Rain", value: "\(Int((rain * 100).rounded()))%", fraction: rain, colour: Ink.rain))
        }
        let suns = Skylight.sunTimes(snapshot, now: now)
        if let rise = suns.first(where: \.rise)?.time, let set = suns.first(where: { !$0.rise })?.time {
            let lit = Cyberpunk.daylight(now: now, rise: rise, set: set)
            out.append(Rune(label: lit == nil ? "Night" : "Daylight", value: "\(clock(rise, zone)) – \(clock(set, zone))", fraction: lit ?? 0))
        }
        return out
    }
}

/// The next 24 hours as the tide of the hours: the temperature as a gold line through its
/// slots, each reading over it and its hour under it, the chance of rain as pale bars.
private struct Tide: View {
    let snapshot: Snapshot
    let weather: Weather
    let now: Date

    var body: some View {
        let zone = snapshot.timeZone
        let points = Skylight.ribbon(weather, now: now)
        if points.count < 2 {
            Text("The hours ahead are unwritten.")
                .font(Face.italic(26)).foregroundStyle(Ink.creamDim)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Canvas { gc, size in paint(points, zone: zone, in: size, &gc) }
        }
    }

    private func paint(_ points: [Skylight.Point], zone: TimeZone, in size: CGSize, _ gc: inout GraphicsContext) {
        let labelTop: CGFloat = 30, labelBottom: CGFloat = 24
        let plot = CGRect(x: 26, y: labelTop, width: size.width - 52, height: size.height - labelTop - labelBottom)
        let temps = points.map(\.temp)
        let lo = temps.min()!, hi = temps.max()!
        let span = max(hi - lo, 4)
        let mid = (hi + lo) / 2
        func x(_ i: Int) -> CGFloat { plot.minX + plot.width * CGFloat(i) / CGFloat(points.count - 1) }
        func y(_ v: Double) -> CGFloat { plot.midY - CGFloat((v - mid) / span) * plot.height * 0.8 }
        // The floor, ruled faintly.
        gc.fill(Path(CGRect(x: plot.minX, y: plot.maxY, width: plot.width, height: 1)), with: .color(Ink.goldDeep.opacity(0.8)))
        for (i, p) in points.enumerated() where p.precipChance > 0.02 {
            let h = plot.height * CGFloat(p.precipChance)
            gc.fill(Path(roundedRect: CGRect(x: x(i) - 8, y: plot.maxY - h, width: 16, height: h), cornerRadius: 2),
                    with: .color(Ink.rain.opacity(0.3)))
            gc.fill(Path(CGRect(x: x(i) - 8, y: plot.maxY - h, width: 16, height: 2)), with: .color(Ink.rain.opacity(0.9)))
        }
        var line = Path()
        for i in points.indices {
            let pt = CGPoint(x: x(i), y: y(points[i].temp))
            i == 0 ? line.move(to: pt) : line.addLine(to: pt)
        }
        gc.drawLayer { l in
            l.addFilter(.blur(radius: 5))
            l.stroke(line, with: .color(Ink.gold.opacity(0.6)), lineWidth: 5)
        }
        gc.stroke(line, with: .color(Ink.gold), lineWidth: 2.2)
        let label = Font.custom("Goodmountain-Regular", size: 22), small = Face.caps(13, 500)
        for (i, p) in points.enumerated() {
            let c = CGPoint(x: x(i), y: y(p.temp))
            var gem = Path()
            let d: CGFloat = p.isNow ? 6 : 4.5
            gem.move(to: CGPoint(x: c.x, y: c.y - d)); gem.addLine(to: CGPoint(x: c.x + d, y: c.y))
            gem.addLine(to: CGPoint(x: c.x, y: c.y + d)); gem.addLine(to: CGPoint(x: c.x - d, y: c.y)); gem.closeSubpath()
            gc.fill(gem, with: .color(p.isNow ? Ink.goldBright : Ink.parchmentDeep))
            gc.stroke(gem, with: .color(Ink.gold), lineWidth: 1.5)
            gc.draw(Text("\(Int(p.temp.rounded()))°").font(label).foregroundColor(p.isNow ? Ink.goldBright : Ink.cream),
                    at: CGPoint(x: c.x, y: c.y - 11), anchor: .bottom)
            let when = p.isNow ? "NOW" : Self.hour(p.time, zone).uppercased()
            gc.draw(Text(when).font(small).tracking(1.2).foregroundColor(p.isNow ? Ink.gold : Ink.goldDim),
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

/// The next five days as small miniatures: the day, its sky, its high and low, its rain.
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
                VStack(spacing: 4) {
                    Caps(isToday ? "Today" : day.date.start(in: zone).formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated)),
                         size: 13, weight: 600, colour: isToday ? Ink.gold : Ink.goldDim, tracking: 0.16)
                    Miniature(icon: day.icon, moonFraction: nil, size: CGSize(width: 108, height: 62))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Gilt("\(Int(day.high.rounded()))°", size: 30)
                        Text("\(Int(day.low.rounded()))°")
                            .font(Face.hand(22, .semibold))
                            .foregroundStyle(Ink.creamDim)
                    }
                    if let chance = day.precipChance, chance >= 0.1 {
                        Caps("\(Int((chance * 100).rounded()))% rain", size: 11, colour: Ink.rain, tracking: 0.1)
                    } else {
                        Caps("Dry", size: 11, colour: Ink.goldDim.opacity(0.8), tracking: 0.1)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - The right-hand pages

/// The moon in a gold ring: its phase and how much shows, its next turning, its rise and set.
private struct Lunar: View {
    let moon: Moon
    let snapshot: Snapshot
    let now: Date

    var body: some View {
        let zone = snapshot.timeZone
        let fraction = moon.days.first { $0.date == CivilDate(now, in: zone) }?.fraction ?? moon.today?.fraction ?? 0
        Panel(title: "The Moon", glyph: "🕯", note: moon.supermoon ? "A supermoon" : nil) {
            HStack(spacing: 22) {
                ZStack {
                    Circle().stroke(Ink.gold.opacity(0.85), lineWidth: 2.5).padding(-8)
                    Circle().stroke(Ink.goldDeep.opacity(0.8), lineWidth: 1).padding(-13)
                    MoonDisc(fraction: fraction, radius: 62, halo: true)
                }
                .frame(width: 124, height: 124)
                .padding(.leading, 14)
                VStack(alignment: .leading, spacing: 4) {
                    Gilt(moon.phaseName, size: 32)
                        .minimumScaleFactor(0.7)
                    Text(Grimoire.moonLine(moon).split(separator: ",").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? "")
                        .font(Face.hand(24)).foregroundStyle(Ink.cream)
                    Caps(Grimoire.nextMoon(moon), size: 14, colour: Ink.gold, tracking: 0.08)
                    if let rise = moon.rise, let set = moon.set {
                        Caps("Rises \(clock(rise, zone)) · Sets \(clock(set, zone))", size: 13, colour: Ink.goldDim, tracking: 0.06)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

/// The day's quote as the words of the sage.
private struct Sage: View {
    let quote: Quote?

    var body: some View {
        Panel(title: "Words of the Sage", glyph: "📖") {
            if let quote {
                VStack(alignment: .leading, spacing: 14) {
                    Text("“\(quote.text)”")
                        .font(Face.italic(33))
                        .foregroundStyle(Ink.cream)
                        .lineSpacing(3)
                        .minimumScaleFactor(0.6)
                        .fixedSize(horizontal: false, vertical: true)
                    Caps("— " + quote.author, size: 17, weight: 600, colour: Ink.gold, tracking: 0.1)
                }
                .padding(.horizontal, 6)
                .padding(.top, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Empty(line: "The sage is silent.", sub: "No words were set down for today.")
                    .frame(maxHeight: .infinity)
            }
        }
    }
}

/// The air as the dragon's breath: sweet or foul, with the index and the fine dust.
private struct Breath: View {
    let air: AirQuality

    var body: some View {
        let colour = Ink.breath(air.band)
        Panel(title: "Dragon’s Breath", glyph: "🐉") {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Gilt(Grimoire.breath(air.band), size: 40, colour: colour)
                Text(air.shortLabel.lowercased())
                    .font(Face.italic(24)).foregroundStyle(Ink.creamDim)
                Spacer(minLength: 0)
                Caps("AQI \(air.aqi) · fine dust \(String(format: "%.0f", air.pm25))", size: 13, colour: Ink.goldDim, tracking: 0.06)
            }
            .padding(.horizontal, 6)
            RuneBar(fraction: Double(air.aqi) / 300, colour: colour)
                .padding(.horizontal, 6)
        }
    }
}

// MARK: - The candles

/// A candle for each source the Pi sends: lit while its data is fresh, guttering as it ages,
/// out once it is stale.
private struct Candles: View {
    let sources: Sources

    var body: some View {
        let candles = Grimoire.candles(sources)
        HStack(spacing: 44) {
            Spacer(minLength: 0)
            ForEach(candles, id: \.name) { name, candle in
                HStack(spacing: 10) {
                    Glyph("🕯", size: 26, colour: colour(candle))
                        .shadow(color: Ink.gold.opacity(candle == .lit ? 0.8 : 0), radius: 7)
                    Caps(name, size: 15, weight: 600, colour: candle == .out ? Ink.ash : Ink.gold, tracking: 0.14)
                    Caps(word(candle), size: 13, colour: candle == .out ? Ink.ash : Ink.goldDim, tracking: 0.1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func colour(_ candle: Grimoire.Candle) -> Color {
        switch candle {
        case .lit: Ink.goldBright
        case .guttering: Ink.goldDim
        case .out: Ink.ash
        }
    }

    private func word(_ candle: Grimoire.Candle) -> String {
        switch candle {
        case .lit: "lit"
        case .guttering: "guttering"
        case .out: "out"
        }
    }
}

/// "9:30 AM" or "21:30", in the zone.
private func clock(_ date: Date, _ zone: TimeZone) -> String {
    let p = ClockTime.parts(date, in: zone)
    return p.period.map { "\(p.time) \($0)" } ?? p.time
}
