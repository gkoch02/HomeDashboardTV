import DashboardCore
import SwiftUI

/// The Pi's `wide_horizon` theme, drawn natively: the next 72 hours on one time axis. The sky
/// across the screen is coloured by the sun's altitude at every moment, so day, twilight and
/// night follow each other left to right; the forecast temperature runs over it as one line,
/// clouds and rain sit on their slots, rain chance hangs beneath, and the calendar's events
/// sit below on the same hours. The conditions now and an outlook fill the left column.
///
/// Laid out as the Pi's 1360x480 plate, with the TV's extra height given to the sky and the
/// event lists. The model is `Horizon` in `DashboardCore`; the sun is the Pi's `sun` block,
/// or without one (no coordinates, an older Pi) the arc between sunrise and sunset, as the
/// panel falls back to. Type is the Pi's own:
/// Big Shoulders Display for names and numbers, Figtree ExtraBold for events, DM Sans for
/// labels.
struct HorizonView: Theme {
    let snapshot: Snapshot
    let now: Date

    static let fullBleed = true

    private var zone: TimeZone { snapshot.timeZone }

    var body: some View {
        GeometryReader { geometry in
            let g = Geometry(size: geometry.size)
            let axis = TimeAxis(start: Horizon.windowStart(now: now, in: zone), x0: g.axisX0, x1: g.axisX1, zone: zone)
            let weather = snapshot.sources.weather?.data
            let slots = Horizon.slots(weather: weather, axis: axis)
            ZStack(alignment: .topLeading) {
                SkyArt(model: SkyModel(snapshot: snapshot, axis: axis, slots: slots), size: g.skySize)
                    .equatable()
                    .frame(width: g.skySize.width, height: g.skySize.height)
                    .offset(x: g.axisX0, y: g.skyY0)

                DayHeaders(axis: axis, now: now, g: g)
                RainAndHours(axis: axis, slots: slots, g: g)
                    .frame(width: geometry.size.width + 24, height: g.eventsY0 - g.skyY1)
                    .offset(y: g.skyY1)
                EventsBand(snapshot: snapshot, axis: axis, g: g)

                // The panel bleeds 24 pt past the top, left and bottom for the drift; its
                // content keeps a 56 x 48 pt margin inside the screen.
                HeroColumn(snapshot: snapshot, now: now, axis: axis, slots: slots)
                    .padding(EdgeInsets(top: 24 + 48, leading: 24 + 56, bottom: 24 + 40, trailing: 28))
                    .frame(width: g.heroW + 24, height: geometry.size.height + 48, alignment: .topLeading)
                    .background(Ink.hero)
                    .offset(x: -24, y: -24)
            }
        }
    }

    var backdrop: some View { Ink.plate }
}

// MARK: - Geometry

/// The plate's bands, top to bottom, right of the hero column.
private struct Geometry {
    let size: CGSize
    let heroW: CGFloat = 440
    let headY0: CGFloat = 0
    let skyY0: CGFloat = 112
    var skyH: CGFloat { max(300, min(440, size.height * 0.40)) }
    var skyY1: CGFloat { skyY0 + skyH }
    let rainH: CGFloat = 58
    let hoursH: CGFloat = 40
    var hoursY0: CGFloat { skyY1 + rainH }
    var eventsY0: CGFloat { hoursY0 + hoursH + 12 }
    var eventsY1: CGFloat { size.height - 40 }
    var axisX0: CGFloat { heroW }
    var axisX1: CGFloat { size.width }
    /// The sky runs past the screen edge so the drift never shows its end.
    var skySize: CGSize { CGSize(width: size.width - heroW + 24, height: skyH) }
}

// MARK: - Inks and faces

private enum Ink {
    static let plate = Color(red: 0.075, green: 0.078, blue: 0.094)
    static let hero = Color(red: 0.030, green: 0.032, blue: 0.040)
    static let cream = Color(red: 0.95, green: 0.93, blue: 0.88)
    static let faint = cream.opacity(0.55)
    static let rule = cream.opacity(0.22)
    static let red = Color(red: 0.93, green: 0.36, blue: 0.30)
    static let yellow = Color(red: 0.98, green: 0.80, blue: 0.33)
    static let rain = Color(red: 0.45, green: 0.66, blue: 0.98)
    static let curve = Color(red: 0.99, green: 0.45, blue: 0.36)
}

private enum Face {
    static let black = "BigShouldersDisplayThin-Black"
    static let extraBold = "BigShouldersDisplayThin-ExtraBold"
    static let title = "Figtree-ExtraBold"
    static let label = "DMSans-9ptRegular"
}

// MARK: - The sky

/// What the sky draws, compared so the minute ticks never repaint it: it changes when the
/// window steps (every three hours) or the forecast does.
private struct SkyModel: Equatable {
    let axis: TimeAxis
    let sun: SunModel
    let slots: [HorizonSlot]
    let extremes: [Extreme]
    let scale: (lo: Double, hi: Double)
    let noons: [Date]
    let noonPeaks: [Double]
    let moons: [Date]
    let moonFractions: [Double]

    init(snapshot: Snapshot, axis: TimeAxis, slots: [HorizonSlot]) {
        self.axis = axis
        let sun = SunModel(snapshot: snapshot)
        self.sun = sun
        self.slots = slots
        extremes = Horizon.extremes(slots, axis: axis)
        scale = Horizon.tempScale(slots)
        let noons = sun.noons(in: axis).filter { !Horizon.hidden(at: $0.time, in: slots) }
        self.noons = noons.map(\.time)
        noonPeaks = noons.map(\.altitude)
        var moons: [(Date, Double)] = []
        if let moon = snapshot.moon {
            var day = CivilDate(axis.start, in: axis.zone).adding(days: -1)
            while day <= CivilDate(axis.end, in: axis.zone) {
                if let m = Horizon.moonTransit(on: day, moon: moon, zone: axis.zone),
                   m.time >= axis.start, m.time <= axis.end,
                   sun.altitude(at: m.time) < -10, !Horizon.hidden(at: m.time, in: slots) {
                    moons.append(m)
                }
                day = day.adding(days: 1)
            }
        }
        self.moons = moons.map(\.0)
        moonFractions = moons.map(\.1)
    }

    static func == (a: SkyModel, b: SkyModel) -> Bool {
        a.axis == b.axis && a.sun == b.sun && a.slots == b.slots && a.moons == b.moons
            && a.moonFractions == b.moonFractions
    }

    /// Altitude at a sky-local x (0 is the axis start).
    func altitude(atLocalX x: Double) -> Double {
        sun.altitude(at: axis.time(atX: axis.x0 + x))
    }

    func localX(_ t: Date) -> Double { axis.x(t) - axis.x0 }
}

/// How far the horizon glow lifts the sky's bottom edge, in degrees of altitude: at dusk the
/// bottom of the band is still orange when the top has gone dark.
private let horizonGlow = 12.0

private struct SkyArt: View, Equatable {
    let model: SkyModel
    let size: CGSize

    static func == (a: SkyArt, b: SkyArt) -> Bool { a.model == b.model && a.size == b.size }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let image = Self.skyImage(model, size: size) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size.width, height: size.height)
            }
            Canvas(rendersAsynchronously: false) { context, _ in
                stars(&context)
                midnights(&context)
                for box in sunBoxes { sun(at: box, &context) }
            }
            ForEach(Array(moonBoxes.enumerated()), id: \.offset) { i, box in
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [.white.opacity(0.16), .white.opacity(0)],
                                             center: .center, startRadius: box.width / 2, endRadius: box.width * 1.3))
                        .frame(width: box.width * 2.6, height: box.width * 2.6)
                    MoonDisc(fraction: model.moonFractions[i], radius: box.width / 2)
                }
                .position(x: box.midX, y: box.midY)
            }
            Canvas(rendersAsynchronously: false) { context, _ in
                weather(&context)
                temperature(&context)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private var bodies: [CGRect] { sunBoxes.map { $0.insetBy(dx: -24, dy: -24) } + moonBoxes }

    private var sunBoxes: [CGRect] {
        zip(model.noons, model.noonPeaks).map { noon, peak in
            let r: CGFloat = 30
            let cy = size.height * 0.10 + size.height * 0.20 * (1 - min(peak, 90) / 90) + r
            let x = max(r + 8, model.localX(noon))  // a noon at the window's start stays whole
            return CGRect(x: x - r, y: cy - r, width: 2 * r, height: 2 * r)
        }
    }

    private var moonBoxes: [CGRect] {
        model.moons.map { t in
            let r: CGFloat = 30
            return CGRect(x: model.localX(t) - r, y: size.height * 0.2 - r, width: 2 * r, height: 2 * r)
        }
    }

    private func isDark(_ x: Double) -> Bool { model.altitude(atLocalX: x) < -9 }

    // MARK: Sky field

    /// The sky as an image a column per 2 pt, interpolated up: altitude per column, the
    /// horizon glow and, by day, a paler haze toward the horizon.
    static func skyImage(_ model: SkyModel, size: CGSize) -> CGImage? {
        let w = max(2, Int(size.width / 2))
        let h = 48
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for i in 0..<w {
            let alt = model.altitude(atLocalX: (Double(i) + 0.5) * size.width / Double(w))
            let haze = alt > 0 ? min(1, alt / 15) * 0.45 : 0
            for j in 0..<h {
                let frac = Double(j) / Double(h - 1)
                var c = skyColour(alt + horizonGlow * frac)
                let k = haze * frac * frac
                c = (c.0 + (0.72 - c.0) * k, c.1 + (0.82 - c.1) * k, c.2 + (0.93 - c.2) * k)
                let o = (j * w + i) * 4
                px[o] = UInt8(max(0, min(255, c.0 * 255)))
                px[o + 1] = UInt8(max(0, min(255, c.1 * 255)))
                px[o + 2] = UInt8(max(0, min(255, c.2 * 255)))
            }
        }
        guard let provider = CGDataProvider(data: Data(px) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Day blue through gold, orange and plum to night, by altitude in degrees.
    private static let stops: [(h: Double, c: (Double, Double, Double))] = [
        (60, (0.10, 0.33, 0.66)),
        (25, (0.20, 0.47, 0.80)),
        (12, (0.46, 0.67, 0.89)),
        (5, (0.93, 0.80, 0.62)),
        (1, (0.99, 0.65, 0.36)),
        (-2, (0.93, 0.44, 0.30)),
        (-5, (0.68, 0.29, 0.38)),
        (-8, (0.34, 0.19, 0.39)),
        (-12, (0.13, 0.12, 0.29)),
        (-16, (0.05, 0.06, 0.15)),
        (-90, (0.025, 0.03, 0.08)),
    ]

    static func skyColour(_ h: Double) -> (Double, Double, Double) {
        if h >= stops[0].h { return stops[0].c }
        for (a, b) in zip(stops, stops.dropFirst()) where h >= b.h {
            let t = (h - b.h) / (a.h - b.h)
            return (b.c.0 + (a.c.0 - b.c.0) * t, b.c.1 + (a.c.1 - b.c.1) * t, b.c.2 + (a.c.2 - b.c.2) * t)
        }
        return stops[stops.count - 1].c
    }

    // MARK: Stars, midnights, the sun

    /// Stars in deep night, seeded per clock hour so they travel with time.
    private func stars(_ context: inout GraphicsContext) {
        let axis = model.axis
        let first = Int(axis.start.timeIntervalSince1970 / 3600)
        for k in 0..<axis.hours {
            let xa = axis.x(axis.start.addingTimeInterval(Double(k) * 3600)) - axis.x0
            let xb = axis.x(axis.start.addingTimeInterval(Double(k + 1) * 3600)) - axis.x0
            var random = SplitMix(seed: UInt64(first + k) &* 7919 &+ 17)
            let n = max(1, Int(((xb - xa) * 12 / 100).rounded()))
            for _ in 0..<n {
                let x = xa + random.unit() * (xb - xa)
                let y = 8 + random.unit() * (size.height * 0.62 - 8)
                let r = 0.7 + pow(random.unit(), 3) * 2.2
                let alpha = 0.35 + random.unit() * 0.6
                let depth = model.altitude(atLocalX: x) + horizonGlow * y / size.height
                guard depth < -15 else { continue }
                let fade = min(1, (-15 - depth) / 5)
                let dot = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                if r > 2 {
                    var glow = context
                    glow.addFilter(.blur(radius: r * 2))
                    glow.fill(dot, with: .color(.white.opacity(alpha * fade * 0.6)))
                }
                context.fill(dot, with: .color(.white.opacity(alpha * fade)))
            }
        }
    }

    private func midnights(_ context: inout GraphicsContext) {
        for m in model.axis.midnights {
            let x = m.x - model.axis.x0
            var line = Path()
            line.move(to: CGPoint(x: x, y: 0))
            line.addLine(to: CGPoint(x: x, y: size.height))
            let ink: Color = isDark(x) ? .white.opacity(0.35) : .black.opacity(0.22)
            context.stroke(line, with: .color(ink), style: StrokeStyle(lineWidth: 2, dash: [2, 7]))
        }
    }

    private func sun(at box: CGRect, _ context: inout GraphicsContext) {
        let c = CGPoint(x: box.midX, y: box.midY)
        let r = box.width / 2
        context.fill(
            Path(ellipseIn: box.insetBy(dx: -r * 2.6, dy: -r * 2.6)),
            with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.85, blue: 0.55).opacity(0.45), .clear]),
                                  center: c, startRadius: r * 0.9, endRadius: r * 3.6)
        )
        context.fill(Path(ellipseIn: box), with: .radialGradient(
            Gradient(colors: [Color(red: 1, green: 0.98, blue: 0.88), Color(red: 1, green: 0.86, blue: 0.50),
                              Color(red: 0.97, green: 0.66, blue: 0.24)]),
            center: CGPoint(x: c.x - r * 0.25, y: c.y - r * 0.25), startRadius: 0, endRadius: r * 1.2
        ))
    }

    // MARK: Clouds and precipitation

    /// Clouds, rain, snow, lightning and fog over each slot's span, each slot seeded by its
    /// clock hour so a cloud belongs to a moment and travels with it as the window moves.
    private func weather(_ context: inout GraphicsContext) {
        let axis = model.axis
        let advance: [Int: Double] = [1: 2.8, 2: 1.5, 3: 0.7]
        let rowH = size.height * 0.30
        for slot in model.slots where slot.end > axis.start && slot.start < axis.end {
            let sky = slot.sky
            let xa = axis.x(max(slot.start, axis.start)) - axis.x0
            let xb = axis.x(min(slot.end, axis.end)) - axis.x0
            var random = SplitMix(seed: UInt64(Int(slot.start.timeIntervalSince1970 / 3600)) &* 104_729 &+ 3)
            if sky.precip == .fog {
                fog(xa, xb, &context)
                continue
            }
            guard sky.level > 0 else { continue }
            var x = xa + random.unit() * 24
            var firstCloud: CGPoint?
            while x < xb {
                let w = (110 + random.unit() * 60) * (sky.level == 3 ? 1.2 : 1)
                let ch = w * (0.42 + random.unit() * 0.10)
                let y = 16 + random.unit() * max(1, rowH - ch)
                let clear = sky.level == 3 || sky.precip != .none
                    || bodies.allSatisfy { abs(x - $0.midX) > 30 + w / 2 }
                if clear {
                    let dark = isDark(x)
                    cloud(CGRect(x: x - w / 2, y: y, width: w, height: ch), dark: dark, random: &random, &context)
                    precipitation(sky.precip, under: CGRect(x: x - w / 2, y: y, width: w, height: ch),
                                  heavy: (slot.precipMm ?? 0) >= 2 || sky.precip == .storm, random: &random, &context)
                    if firstCloud == nil { firstCloud = CGPoint(x: x, y: y + ch) }
                }
                x += w * (advance[sky.level] ?? 1.5) * (0.85 + random.unit() * 0.3)
            }
            if sky.precip == .storm, let base = firstCloud { bolt(at: base, &context) }
        }
    }

    /// A cumulus: a flat base under puffs rising toward the middle, lit from above.
    private func cloud(_ rect: CGRect, dark: Bool, random: inout SplitMix, _ context: inout GraphicsContext) {
        let w = rect.width, h = rect.height
        var path = Path(roundedRect: CGRect(x: rect.minX, y: rect.maxY - h * 0.36, width: w, height: h * 0.36),
                        cornerRadius: h * 0.18)
        let n = 3 + Int(random.unit() * 3)
        for i in 0..<n {
            let f = (Double(i) + 0.5) / Double(n)
            let cx = rect.minX + w * f + (random.unit() - 0.5) * w * 0.08
            var r = h * (0.20 + 0.26 * sin(.pi * f)) * (0.9 + random.unit() * 0.22)
            r = min(r, h * 0.8 / 1.6)
            let cy = max(rect.minY + r, rect.maxY - h * 0.26 - r * 0.6)
            path.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
        }
        let (lit, shade): (Color, Color) = dark
            ? (Color(red: 0.36, green: 0.39, blue: 0.48), Color(red: 0.13, green: 0.15, blue: 0.21))
            : (Color(red: 0.99, green: 0.98, blue: 0.96), Color(red: 0.66, green: 0.71, blue: 0.79))
        var under = context
        under.addFilter(.blur(radius: h * 0.12))
        under.fill(path.offsetBy(dx: 0, dy: h * 0.08), with: .color(.black.opacity(dark ? 0.35 : 0.18)))
        context.fill(path, with: .linearGradient(Gradient(colors: [lit, shade]),
                                                 startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                                 endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
    }

    private func precipitation(_ precip: SkyKind.Precip, under rect: CGRect, heavy: Bool,
                               random: inout SplitMix, _ context: inout GraphicsContext) {
        let ink = Color(red: 0.80, green: 0.87, blue: 0.97)
        switch precip {
        case .rain, .storm:
            var streaks = Path()
            var sx = rect.minX + 14
            while sx < rect.maxX - 10 {
                let sy = rect.maxY + 6 + random.unit() * 14
                let len = 18 + random.unit() * 16
                streaks.move(to: CGPoint(x: sx, y: sy))
                streaks.addLine(to: CGPoint(x: sx - len * 0.3, y: sy + len))
                sx += heavy ? 9 : 14
            }
            context.stroke(streaks, with: .color(ink.opacity(0.75)),
                           style: StrokeStyle(lineWidth: heavy ? 3 : 2, lineCap: .round))
        case .snow:
            for _ in 0..<Int(rect.width / 7) {
                let x = rect.minX + 10 + random.unit() * (rect.width - 20)
                let y = rect.maxY + 8 + random.unit() * 54
                let r = 1.8 + random.unit() * 2.4
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)),
                             with: .color(.white.opacity(0.9)))
            }
        default:
            break
        }
    }

    private func bolt(at base: CGPoint, _ context: inout GraphicsContext) {
        let s = 2.0
        let pts = [(3, -2), (-7, 18), (1, 18), (-9, 40), (12, 12), (4, 12), (12, -2)]
            .map { CGPoint(x: base.x + Double($0.0) * s, y: base.y + Double($0.1) * s) }
        var path = Path()
        path.addLines(pts)
        path.closeSubpath()
        var glow = context
        glow.addFilter(.blur(radius: 10))
        glow.fill(path, with: .color(Ink.yellow.opacity(0.8)))
        context.fill(path, with: .color(Color(red: 1, green: 0.93, blue: 0.62)))
    }

    /// Mist as soft dashed bands across the slot, after the Pi's dashed rules.
    private func fog(_ xa: Double, _ xb: Double, _ context: inout GraphicsContext) {
        var bands = context
        bands.addFilter(.blur(radius: 2))
        for i in 0..<4 {
            let y = size.height * (0.50 + 0.1 * Double(i))
            var line = Path()
            line.move(to: CGPoint(x: xa + Double(i % 2) * 20, y: y))
            line.addLine(to: CGPoint(x: xb, y: y))
            bands.stroke(line, with: .color(.white.opacity(0.42)),
                         style: StrokeStyle(lineWidth: 7, lineCap: .round, dash: [28, 16]))
        }
    }

    // MARK: Temperature

    private func temperature(_ context: inout GraphicsContext) {
        let slots = model.slots
        guard slots.count >= 2 else { return }
        let (lo, hi) = model.scale
        // The Pi's band runs to 86 % of the sky; here it stops at 78 % so a low's label, set
        // larger, fits beneath it.
        let top = size.height * 0.40
        let bottom = size.height * 0.78
        func y(_ temp: Double) -> Double { bottom - (temp - lo) / (hi - lo) * (bottom - top) }
        let points = slots.map { CGPoint(x: model.axis.xUnclamped($0.start) - model.axis.x0, y: y($0.temp)) }
        let curve = catmullRom(points)

        var shadow = context
        shadow.addFilter(.blur(radius: 6))
        shadow.stroke(curve, with: .color(.black.opacity(0.45)),
                      style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
        context.stroke(curve, with: .color(Ink.curve), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))

        var placed: [CGRect] = bodies
        for e in model.extremes {
            let p = CGPoint(x: model.localX(e.time), y: y(e.temp))
            let text = context.resolve(Text("\(Int(e.temp.rounded()))°")
                .font(.custom(Face.extraBold, size: 52)).foregroundStyle(.white))
            let m = text.measure(in: CGSize(width: 400, height: 200))
            let ty = e.kind == .high ? p.y - m.height - 12 : p.y + 18
            var box = CGRect(x: min(max(4, p.x - m.width / 2), size.width - m.width - 28), y: ty,
                             width: m.width, height: m.height)
            if box.minY < 4 || box.maxY > size.height - 4 {
                // No room above or below: beside the point instead, clear of the sky's edge.
                box.origin = CGPoint(x: p.x + 16, y: min(max(4, p.y - m.height / 2), size.height - m.height - 4))
            }
            if let hit = placed.first(where: { $0.insetBy(dx: -4, dy: -4).intersects(box) }) {
                let right = box.offsetBy(dx: hit.maxX + 6 - box.minX, dy: 0)
                let left = box.offsetBy(dx: hit.minX - 6 - box.maxX, dy: 0)
                box = [right, left].min { abs($0.midX - p.x) < abs($1.midX - p.x) }!
            }
            placed.append(box)
            var label = context
            label.addFilter(.shadow(color: .black.opacity(0.7), radius: 6))
            label.draw(text, in: box)
            let dot = Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14))
            context.fill(dot, with: .color(.white))
            context.stroke(dot, with: .color(Ink.curve), lineWidth: 3)
        }
    }

    /// A smooth path through *points* (x increasing).
    private func catmullRom(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        let p = [first] + points + [points[points.count - 1]]
        for i in 1..<(p.count - 2) {
            let (p0, p1, p2, p3) = (p[i - 1], p[i], p[i + 1], p[i + 2])
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }
}

// MARK: - Day headers

private struct DayHeaders: View {
    let axis: TimeAxis
    let now: Date
    let g: Geometry

    var body: some View {
        let today = CivilDate(now, in: axis.zone)
        ForEach(axis.dayColumns, id: \.day) { column in
            let room = column.x1 - column.x0 - 28
            let name = Horizon.dayName(column.day, now: now, axis: axis)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    headline(name, today: column.day == today)
                    Text(dateLabel(column.day))
                        .font(.custom(Face.label, size: 24).weight(.bold))
                        .foregroundStyle(Ink.faint)
                }
                headline(name, today: column.day == today)
                if column.day == today {
                    Text(name)
                        .font(.custom(Face.label, size: 24).weight(.bold))
                        .foregroundStyle(Ink.red)
                } else {
                    headline(short(column.day), today: false)
                }
                Color.clear.frame(width: 0, height: 0)
            }
            .frame(width: max(0, room), height: 70, alignment: .bottomLeading)
            .offset(x: column.x0 + 16, y: g.skyY0 - 84)
        }
        ForEach(axis.midnights, id: \.day) { m in
            Rectangle().fill(Ink.rule)
                .frame(width: 2, height: g.skyY0 - 20)
                .offset(x: m.x - 1, y: 20)
        }
    }

    private func headline(_ text: String, today: Bool) -> some View {
        Text(text)
            .font(.custom(Face.black, size: 64))
            .foregroundStyle(today ? Ink.red : Ink.cream)
            .lineLimit(1)
            .fixedSize()
    }

    private func dateLabel(_ day: CivilDate) -> String {
        day.start(in: axis.zone).formatted(Date.FormatStyle(timeZone: axis.zone).month(.abbreviated).day()).uppercased()
    }

    private func short(_ day: CivilDate) -> String {
        day.start(in: axis.zone).formatted(Date.FormatStyle(timeZone: axis.zone).weekday(.abbreviated)).uppercased()
    }
}

// MARK: - Rain and hours

/// Each slot's chance of rain as a bar hanging from the sky, its depth the chance and its
/// strength the amount; then the hour ticks; the midnight rules run down through both.
private struct RainAndHours: View {
    let axis: TimeAxis
    let slots: [HorizonSlot]
    let g: Geometry

    var body: some View {
        Canvas { context, size in
            var stretches: [[HorizonSlot]] = [[]]
            for s in slots {
                guard s.end > axis.start, s.start < axis.end, s.precipChance >= 0.1 else {
                    if !stretches[stretches.count - 1].isEmpty { stretches.append([]) }
                    continue
                }
                let x0 = axis.x(s.start), x1 = axis.x(s.end)
                let depth = max(3, (g.rainH - 26) * s.precipChance)
                let cover = Horizon.rainCover(mm: s.precipMm, chance: s.precipChance)
                let bar = CGRect(x: x0 + 1, y: 0, width: max(0, x1 - x0 - 2), height: depth)
                context.fill(Path(bar), with: .linearGradient(
                    Gradient(colors: [Ink.rain.opacity(0.25 + 0.55 * cover), Ink.rain.opacity(0.15 + 0.35 * cover)]),
                    startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: depth)))
                context.fill(Path(CGRect(x: bar.minX, y: depth - 2, width: bar.width, height: 2)),
                             with: .color(Ink.rain.opacity(0.9)))
                stretches[stretches.count - 1].append(s)
            }
            for run in stretches where !run.isEmpty {
                guard let peak = run.max(by: { $0.precipChance < $1.precipChance }), peak.precipChance >= 0.3 else { continue }
                let text = context.resolve(Text("\(Int((peak.precipChance * 100).rounded()))%")
                    .font(.custom(Face.label, size: 20).weight(.semibold)).foregroundStyle(Ink.rain))
                let x = min(max(axis.x0 + 30, (axis.x(peak.start) + axis.x(peak.end)) / 2), axis.x1 - 40)
                context.draw(text, at: CGPoint(x: x, y: max(3, (g.rainH - 26) * peak.precipChance) + 2), anchor: .top)
            }

            let y0 = g.rainH
            context.fill(Path(CGRect(x: axis.x0, y: y0, width: size.width - axis.x0, height: 1.5)), with: .color(Ink.rule))
            for t in axis.labelledHours {
                let x = axis.x(t)
                context.fill(Path(CGRect(x: x - 1, y: y0, width: 2, height: 8)), with: .color(Ink.faint))
                let text = context.resolve(Text(CompactTime.string(t, in: axis.zone))
                    .font(.custom(Face.label, size: 22).weight(.semibold)).foregroundStyle(Ink.faint))
                let w = text.measure(in: CGSize(width: 200, height: 50)).width
                if x - w / 2 > axis.x0 + 4 && x + w / 2 < axis.x1 - 8 {
                    context.draw(text, at: CGPoint(x: x, y: y0 + 9), anchor: .top)
                }
            }
            for m in axis.midnights {
                context.fill(Path(CGRect(x: m.x - 1, y: 0, width: 2, height: size.height)), with: .color(Ink.rule))
            }
        }
    }
}

// MARK: - Events

/// The schedule strip, all-day chips, then each day's events in its own column.
private struct EventsBand: View {
    let snapshot: Snapshot
    let axis: TimeAxis
    let g: Geometry

    private static let stripH: CGFloat = 14
    private static let chipH: CGFloat = 42
    private static let rowH: CGFloat = 50
    private static let maxChipRows = 2
    private static let minColumnW: CGFloat = 150

    private struct PlacedChip: Hashable {
        var row: Int
        var x0: CGFloat
        var x1: CGFloat
        var label: String
        var isBirthday: Bool
        var start: Date
    }

    var body: some View {
        let events = Horizon.timedEvents(snapshot, axis: axis)
        let chips = placedChips()
        let hidden = hiddenChips()
        let chipsY = g.eventsY0 + Self.stripH + 16
        ZStack(alignment: .topLeading) {
            ForEach(axis.midnights, id: \.day) { m in
                Rectangle().fill(Ink.rule)
                    .frame(width: 2, height: g.eventsY1 - g.eventsY0 + 12)
                    .offset(x: m.x - 1, y: g.eventsY0 - 12)
            }
            Rectangle().fill(Ink.rule)
                .frame(width: axis.x1 - axis.x0 + 24, height: 1.5)
                .offset(x: axis.x0, y: g.eventsY0 + Self.stripH)
            ForEach(Array(events.enumerated()), id: \.offset) { _, e in
                let x0 = axis.x(e.start).rounded() + 2
                let x1 = max(axis.x(e.end).rounded() - 2, x0 + 5)
                RoundedRectangle(cornerRadius: 2).fill(Ink.cream.opacity(0.9))
                    .frame(width: x1 - x0, height: Self.stripH)
                    .offset(x: x0, y: g.eventsY0)
            }
            ForEach(chips, id: \.self) { chip in
                chipView(chip)
                    .frame(width: chip.x1 - chip.x0, height: Self.chipH - 8)
                    .offset(x: chip.x0, y: chipsY + CGFloat(chip.row) * Self.chipH)
            }
            ForEach(axis.dayColumns, id: \.day) { column in
                dayList(column: column, events: events, chips: chips, hidden: hidden, chipsY: chipsY)
            }
        }
    }

    @ViewBuilder private func chipView(_ chip: PlacedChip) -> some View {
        let label = Text(chip.x1 - chip.x0 >= 70 ? chip.label : "")
            .font(.custom(Face.label, size: 22).weight(.bold))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        if chip.isBirthday {
            label.foregroundStyle(Ink.red)
                .background(RoundedRectangle(cornerRadius: 4).strokeBorder(Ink.red, lineWidth: 2.5))
        } else {
            label.foregroundStyle(Ink.cream)
                .background(RoundedRectangle(cornerRadius: 4).fill(Ink.red))
        }
    }

    private func chipItems() -> [(x0: Double, x1: Double, multiDay: Bool, chip: PlacedChip)] {
        Horizon.allDayChips(snapshot, axis: axis).map { c in
            let x0 = axis.x(c.start), x1 = axis.x(c.end)
            let label = Self.width(c.label) + 24 <= x1 - x0 ? c.label : c.short
            let lw = Self.width(label) + 24
            return (x0, max(x1, x0 + lw), c.end.timeIntervalSince(c.start) > 86_400 + 3600,
                    PlacedChip(row: 0, x0: x0 + 3, x1: x1 - 4, label: label, isBirthday: c.isBirthday, start: c.start))
        }
    }

    private func placedChips() -> [PlacedChip] {
        Horizon.stackChips(chipItems()).prefix(Self.maxChipRows).enumerated().flatMap { row, chips in
            chips.map { var c = $0; c.row = row; return c }
        }
    }

    /// Chips past the rows shown; each counts toward "+N more" on every day it covers.
    private func hiddenChips() -> [PlacedChip] {
        Horizon.stackChips(chipItems()).dropFirst(Self.maxChipRows).flatMap { $0 }
    }

    /// A rough width for a chip label in its face, for choosing the short form.
    private static func width(_ text: String) -> Double { Double(text.count) * 12.5 }

    @ViewBuilder private func dayList(column: (x0: Double, x1: Double, day: CivilDate), events: [CalendarEvent],
                                      chips: [PlacedChip], hidden: [PlacedChip], chipsY: CGFloat) -> some View {
        let dayEvents = events.filter { Horizon.columnDay($0, axis: axis) == column.day }
        let hiddenHere = hidden.filter { $0.x0 < column.x1 && $0.x1 > column.x0 }.count
        let depth = (chips.filter { $0.x0 < column.x1 && $0.x1 > column.x0 }.map(\.row).max()).map { $0 + 1 } ?? 0
        let top = chipsY + CGFloat(depth) * Self.chipH + 4
        let available = max(0, Int((g.eventsY1 - top) / Self.rowH))
        let left = column.x0 + 16
        let width = min(column.x1, axis.x1 - 40) - left - 14
        if width < Self.minColumnW {
            let count = dayEvents.count + hiddenHere
            if count > 0 {
                Text("+\(count)")
                    .font(.custom(Face.title, size: 28))
                    .foregroundStyle(Ink.faint)
                    .offset(x: left, y: top + 6)
            }
        } else {
            let rows = Horizon.listRows(events: dayEvents.count, hidden: hiddenHere, available: available)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 0) {
                ForEach(Array(dayEvents.prefix(rows.shown).enumerated()), id: \.offset) { _, e in
                    GridRow {
                        Text(Horizon.rowTime(e, axis: axis))
                            .font(.custom(Face.title, size: 28))
                            .foregroundStyle(Ink.faint)
                        Text(e.summary)
                            .font(.custom(Face.title, size: 34))
                            .foregroundStyle(Ink.cream)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: Self.rowH)
                }
                if rows.more > 0 {
                    GridRow {
                        Text("+\(rows.more) more")
                            .font(.custom(Face.title, size: 28))
                            .foregroundStyle(Ink.red)
                            .gridCellColumns(2)
                    }
                    .frame(height: Self.rowH)
                }
            }
            .frame(width: width, alignment: .topLeading)
            .offset(x: left, y: top)
        }
    }
}

// MARK: - The hero column

/// The conditions now, the outlook, and when the Pi last read the weather.
private struct HeroColumn: View {
    let snapshot: Snapshot
    let now: Date
    let axis: TimeAxis
    let slots: [HorizonSlot]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("NOW")
                .font(.custom(Face.label, size: 22).weight(.bold))
                .tracking(2)
                .foregroundStyle(Ink.yellow)
            if let weather = snapshot.sources.weather?.data {
                reading(weather)
            } else {
                Text("NO DATA")
                    .font(.custom(Face.black, size: 80))
                    .foregroundStyle(Ink.cream)
            }
            Spacer(minLength: 20)
            outlook
            foot
                .padding(.top, 22)
        }
        .foregroundStyle(Ink.cream)
    }

    @ViewBuilder private func reading(_ w: Weather) -> some View {
        Text("\(Int(w.currentTemp.rounded()))°")
            .font(.custom(Face.black, size: 230))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.top, -14)
            .padding(.bottom, -22)
        Text(w.currentDescription.uppercased())
            .font(.custom(Face.extraBold, size: 50))
            .lineLimit(2)
            .minimumScaleFactor(0.7)
        Text("H \(Int(w.high.rounded()))°   L \(Int(w.low.rounded()))°")
            .font(.custom(Face.label, size: 28).weight(.semibold))
            .padding(.top, 10)
        if let extras = extras(w) {
            Text(extras)
                .font(.custom(Face.label, size: 25).weight(.semibold))
                .foregroundStyle(Ink.cream.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 8)
        }
        if let rise = w.sunrise, let set = w.sunset {
            HStack(spacing: 22) {
                Label(CompactTime.string(rise, in: axis.zone), systemImage: "sunrise.fill")
                Label(CompactTime.string(set, in: axis.zone), systemImage: "sunset.fill")
            }
            .font(.custom(Face.label, size: 25).weight(.semibold))
            .foregroundStyle(Ink.cream.opacity(0.85))
            .padding(.top, 10)
        }
        if let alert = w.alerts.first {
            Text("! \(alert.event.uppercased())")
                .font(.custom(Face.label, size: 22).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Ink.red)
                .padding(.top, 18)
        }
    }

    private func extras(_ w: Weather) -> String? {
        var parts: [String] = []
        if let feels = w.feelsLike { parts.append("Feels \(Int(feels.rounded()))°") }
        if let speed = w.windSpeed {
            var wind = "\(Int(speed.rounded())) \(snapshot.isMetric ? "m/s" : "mph")"
            if let deg = w.windDeg { wind += " \(Self.compass(deg))" }
            parts.append(wind)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    static func compass(_ deg: Double) -> String {
        let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let i = Int((deg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 22.5 + 0.5) % 16
        return points[i]
    }

    @ViewBuilder private var outlook: some View {
        let rows = Horizon.outlook(slots, axis: axis)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Rectangle().fill(Ink.cream.opacity(0.4)).frame(height: 1.5)
                ForEach(rows, id: \.label) { row in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(row.label)
                            .font(.custom(Face.label, size: 18).weight(.bold))
                            .tracking(1.5)
                            .foregroundStyle(Ink.yellow)
                        Text(row.value)
                            .font(.custom(Face.extraBold, size: 40))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
            }
        }
    }

    private var foot: some View {
        let stamp = snapshot.sources.weather?.fetchedAt ?? snapshot.generatedAt
        let parts = [snapshot.sources.weather?.data?.locationName, "updated \(CompactTime.string(stamp, in: axis.zone))"]
            .compactMap { $0 }
        return Text(parts.joined(separator: "  ·  "))
            .font(.custom(Face.label, size: 20).weight(.semibold))
            .foregroundStyle(Ink.faint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}
