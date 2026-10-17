import DashboardCore
import SwiftUI

/// A layout drawn for the TV rather than ported from the Pi: a brass orrery on black, with an
/// almanac beside it.
///
/// The sun sits at the centre over a gear train that ticks once a second. Mercury, Venus, the
/// earth and Mars stand on their arms where they are in their orbits today (`Orrery`), each lit
/// on its sunward side, inside a limb engraved with the months and every day of the year, so
/// the earth's arm points at today's date. Round the earth the moon rides its orbit at tonight's
/// phase, and a ring of 24 hours turns with the earth: noon faces the sun, a hand marks the
/// time here, and the next day's events are enamelled on the ring as arcs.
///
/// Beside it, the almanac: the time; sunrise, sunset and how the daylight is changing; the
/// moon's phase and the next full or new moon; days to the next solstice or equinox; and the
/// events on the ring.
///
/// As the layout appears the instrument comes up and the planets swing round into place on
/// their arms; the almanac rises in beside it.
struct OrreryView: Theme {
    let snapshot: Snapshot
    let now: Date

    @State private var build = OrreryBuild.start

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let d = min(size.height, size.width * 0.56)
            HStack(alignment: .center, spacing: 70) {
                Instrument(snapshot: snapshot, now: now, swing: build.swing)
                    .frame(width: d, height: d)
                    .opacity(build.plate)
                    .scaleEffect(0.96 + 0.04 * build.plate)
                Almanac(snapshot: snapshot, now: now, rise: build.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: size.width, height: size.height)
        }
        .onBuildIn(reset: { settled in build = settled ? .settled : .start }) {
            withAnimation(.easeOut(duration: 0.9)) { build.plate = 1 }
            // Long and gentle, never past the mark: a spring's overshoot carried the planets past
            // their places and back.
            withAnimation(.timingCurve(0.25, 0.1, 0.15, 1, duration: 2.8).delay(0.4)) { build.swing = 1 }
            withAnimation(.linear(duration: 1.4).delay(0.9)) { build.text = 1 }
        }
    }

    var backdrop: some View { Color.black }
}

/// How far the build-in has got, each part 0 to 1.
private struct OrreryBuild {
    var plate: Double
    var swing: Double
    var text: Double

    static let start = OrreryBuild(plate: 0, swing: 0, text: 0)
    static let settled = OrreryBuild(plate: 1, swing: 1, text: 1)
}

private enum Ink {
    static let ivory = Color(red: 0.93, green: 0.89, blue: 0.80)
    static let soft = ivory.opacity(0.72)
    static let faint = ivory.opacity(0.5)
    static let engraving = ivory.opacity(0.3)
    static let brass = Color(red: 0.86, green: 0.70, blue: 0.38)
    static let deepBrass = Color(red: 0.55, green: 0.40, blue: 0.16)

    /// The enamels the events are picked out in, on the ring and beside the almanac's lines.
    static let events: [Color] = [
        Color(red: 0.88, green: 0.36, blue: 0.27),
        Color(red: 0.95, green: 0.72, blue: 0.30),
        Color(red: 0.36, green: 0.70, blue: 0.68),
        Color(red: 0.62, green: 0.45, blue: 0.82),
    ]

    /// Polished brass round a bezel: light catching the top left and the lower right.
    static let brassRing = Gradient(colors: [
        Color(red: 0.98, green: 0.88, blue: 0.58), Color(red: 0.62, green: 0.45, blue: 0.18),
        Color(red: 0.90, green: 0.74, blue: 0.40), Color(red: 0.55, green: 0.40, blue: 0.16),
        Color(red: 0.98, green: 0.88, blue: 0.58),
    ])
}

private enum Face {
    /// Engraved words.
    static func engraved(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .custom("Cinzel", size: size).weight(weight)
    }

    /// The almanac's lines and figures.
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

/// A point *radius* from *centre* at *degrees*, anticlockwise from three o'clock.
private func at(_ centre: CGPoint, _ radius: CGFloat, _ degrees: Double) -> CGPoint {
    let a = degrees * .pi / 180
    return CGPoint(x: centre.x + radius * CGFloat(cos(a)), y: centre.y - radius * CGFloat(sin(a)))
}

private func circle(_ centre: CGPoint, _ radius: CGFloat) -> Path {
    Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
}

/// The orbits' radii, as shares of the instrument's.
private enum Orbit {
    static let mercury: CGFloat = 0.19
    static let venus: CGFloat = 0.3
    static let earth: CGFloat = 0.56
    static let mars: CGFloat = 0.75
    /// Round the earth: its day ring, and the moon's orbit.
    static let day: CGFloat = 0.1
    static let moon: CGFloat = 0.16
    /// The limb, engraved with the year.
    static let limbInner: CGFloat = 0.83
    static let limbOuter: CGFloat = 0.965
}

// MARK: - The instrument

private struct Instrument: View {
    let snapshot: Snapshot
    let now: Date
    let swing: Double

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let r = side / 2
            ZStack {
                Plate(year: CivilDate(now, in: snapshot.timeZone).year, zone: snapshot.timeZone)
                Gears(radius: r)
                Mechanism(state: Mechanism.State(snapshot: snapshot, now: now), swing: swing)
            }
            .frame(width: side, height: side)
        }
    }
}

/// What stays put: the bezel, the limb engraved with the months and days, the enamel plate
/// and the orbits.
private struct Plate: View, Equatable {
    let year: Int
    let zone: TimeZone

    var body: some View {
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2

            // The limb's enamel, the plate's, and the bezel round them.
            context.fill(circle(c, r * Orbit.limbOuter), with: .color(Color(red: 0.05, green: 0.046, blue: 0.042)))
            context.fill(circle(c, r * Orbit.limbInner), with: .radialGradient(
                Gradient(colors: [Color(red: 0.06, green: 0.058, blue: 0.056), .black]),
                center: c, startRadius: 0, endRadius: r * Orbit.limbInner))
            let bezel = r * 0.035
            context.stroke(circle(c, r - bezel / 2), with: .conicGradient(Ink.brassRing, center: c, angle: .degrees(-135)),
                           lineWidth: bezel)
            for edge in [Orbit.limbInner, Orbit.limbOuter] {
                context.stroke(circle(c, r * edge), with: .color(Ink.brass.opacity(0.55)), lineWidth: 1.5)
            }

            // Every day of the year at the earth's place on it, longer at each month's start.
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = zone
            let jan1 = cal.date(from: DateComponents(year: year, month: 1, day: 1, hour: 12))!
            let days = cal.range(of: .day, in: .year, for: jan1)?.count ?? 365
            var ticks = Path(), majors = Path()
            for i in 0..<days {
                let day = cal.date(byAdding: .day, value: i, to: jan1)!
                let a = Orrery.longitude(.earth, at: day)
                let dom = cal.component(.day, from: day)
                let length: CGFloat = dom == 1 ? 0.06 : dom % 5 == 0 ? 0.03 : 0.016
                var path = Path()
                path.move(to: at(c, r * Orbit.limbInner, a))
                path.addLine(to: at(c, r * (Orbit.limbInner + length), a))
                if dom == 1 { majors.addPath(path) } else { ticks.addPath(path) }
            }
            context.stroke(ticks, with: .color(Ink.engraving), lineWidth: 1)
            context.stroke(majors, with: .color(Ink.brass.opacity(0.8)), lineWidth: 2)

            // The months' names, set round the limb at mid-month, upright across the bottom.
            let names = DateFormatter().shortStandaloneMonthSymbols ?? []
            for month in 1...12 {
                let mid = cal.date(from: DateComponents(year: year, month: month, day: 15, hour: 12))!
                let a = Orrery.longitude(.earth, at: mid)
                let p = at(c, r * (Orbit.limbInner + 0.087), a)
                var turn = 90 - a
                if sin(a * .pi / 180) < -0.05 { turn += 180 }
                var label = context
                label.translateBy(x: p.x, y: p.y)
                label.rotate(by: .degrees(turn))
                label.draw(Text(names[month - 1].uppercased())
                    .font(Face.engraved(r * 0.036))
                    .tracking(r * 0.004)
                    .foregroundStyle(Ink.faint), at: .zero)
            }

            // A guilloché rosette engraved in the enamel: circles through the centre, turned a
            // little each, their overlaps making the pattern.
            var rosette = Path()
            for k in 0..<72 {
                rosette.addPath(circle(at(c, r * 0.41, Double(k) * 5), r * 0.41))
            }
            context.stroke(rosette, with: .color(Ink.ivory.opacity(0.05)), lineWidth: 0.8)

            // The bezel's milled edge, and four slotted screws holding it.
            var milling = Path()
            for k in 0..<360 {
                milling.move(to: at(c, r * 0.999, Double(k)))
                milling.addLine(to: at(c, r * 0.986, Double(k)))
            }
            context.stroke(milling, with: .color(.black.opacity(0.35)), lineWidth: 1)
            for a in [45.0, 135, 225, 315] {
                let p = at(c, r - bezel / 2, a)
                context.fill(circle(p, r * 0.012), with: .radialGradient(
                    Gradient(colors: [Color(red: 0.98, green: 0.9, blue: 0.62), Ink.deepBrass]),
                    center: CGPoint(x: p.x - r * 0.004, y: p.y - r * 0.004), startRadius: 0, endRadius: r * 0.014))
                var slot = Path()
                slot.move(to: at(p, r * 0.009, a + 30))
                slot.addLine(to: at(p, r * 0.009, a + 210))
                context.stroke(slot, with: .color(.black.opacity(0.7)), lineWidth: r * 0.003)
            }

            // The orbits, engraved; the earth's a little brighter.
            for (orbit, alpha) in [(Orbit.mercury, 0.22), (Orbit.venus, 0.22), (Orbit.earth, 0.4), (Orbit.mars, 0.22)] {
                context.stroke(circle(c, r * orbit), with: .color(Ink.ivory.opacity(alpha)), lineWidth: 1)
            }
        }
    }
}

/// The gear train under the sun, ticking a tooth a second as a clock's escapement lets it.
private struct Gears: View {
    let radius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            let beat = floor(t) + Self.ease(t - floor(t))
            ZStack {
                Gear(teeth: 40)
                    .frame(width: radius * 0.29, height: radius * 0.29)
                    .rotationEffect(.degrees(beat * 360 / 40))
                Gear(teeth: 16)
                    .frame(width: radius * 0.13, height: radius * 0.13)
                    .rotationEffect(.degrees(-beat * 360 / 16 + 360 / 32))
                    .offset(x: radius * 0.2 * CGFloat(cos(.pi * 1.25)), y: -radius * 0.2 * CGFloat(sin(.pi * 1.25)))
                Gear(teeth: 12)
                    .frame(width: radius * 0.1, height: radius * 0.1)
                    .rotationEffect(.degrees(-beat * 360 / 12))
                    .offset(x: radius * 0.185 * CGFloat(cos(Double.pi / 3)), y: -radius * 0.185 * CGFloat(sin(Double.pi / 3)))
            }
        }
    }

    /// A tick: most of the move in the first sixth of the second, then still.
    private static func ease(_ f: Double) -> Double {
        let x = min(f / 0.16, 1)
        return 1 - pow(1 - x, 3)
    }
}

/// A brass wheel, as in a watch: toothed rim, five curved spokes, and a jewel at the pivot.
private struct Gear: View, Equatable {
    let teeth: Int

    var body: some View {
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2
            let depth = r * 0.12
            var rim = Path()
            for i in 0..<teeth {
                let step = 360 / Double(teeth)
                let a = Double(i) * step
                let corners = [(r - depth, a), (r, a + step * 0.15), (r, a + step * 0.45), (r - depth, a + step * 0.6)]
                for (j, (radius, angle)) in corners.enumerated() {
                    let p = at(c, radius, angle)
                    if i == 0 && j == 0 { rim.move(to: p) } else { rim.addLine(to: p) }
                }
            }
            rim.closeSubpath()
            rim.addPath(circle(c, r * 0.72))
            for k in 0..<5 {
                let a = Double(k) * 72
                var spoke = Path()
                spoke.move(to: at(c, r * 0.14, a))
                spoke.addQuadCurve(to: at(c, r * 0.74, a + 24), control: at(c, r * 0.5, a - 8))
                context.stroke(spoke, with: .color(Ink.deepBrass), style: StrokeStyle(lineWidth: r * 0.08, lineCap: .round))
            }
            let shade = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [Ink.brass, Ink.deepBrass]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height))
            context.fill(rim, with: shade, style: FillStyle(eoFill: true))
            context.stroke(circle(c, r * 0.72), with: .color(Ink.brass.opacity(0.6)), lineWidth: 1)
            context.fill(circle(c, r * 0.18), with: shade)
            // The jewel: a ruby bearing with a glint.
            context.fill(circle(c, r * 0.08), with: .radialGradient(
                Gradient(colors: [Color(red: 1, green: 0.55, blue: 0.6), Color(red: 0.6, green: 0.04, blue: 0.12)]),
                center: CGPoint(x: c.x - r * 0.02, y: c.y - r * 0.02), startRadius: 0, endRadius: r * 0.09))
        }
        .opacity(0.8)
    }
}

/// What moves: the arms, the planets, the sun, and round the earth its day ring, its hand and
/// the moon. Animatable, so the planets swing round into place as the layout appears.
private struct Mechanism: View, Animatable {
    struct State: Equatable {
        /// Each planet's place in its orbit, in degrees.
        var mercury, venus, earth, mars: Double
        /// The moon's angle from the sun, seen from the earth.
        var elongation: Double?
        /// The time here, in hours from midnight.
        var hour: Double
        /// The events on the ring: from and to, in hours from today's midnight.
        var events: [ClosedRange<Double>]

        init(snapshot: Snapshot, now: Date) {
            let zone = snapshot.timeZone
            mercury = Orrery.longitude(.mercury, at: now)
            venus = Orrery.longitude(.venus, at: now)
            earth = Orrery.longitude(.earth, at: now)
            mars = Orrery.longitude(.mars, at: now)
            let midnight = CivilDate(now, in: zone).start(in: zone)
            let hours = now.timeIntervalSince(midnight) / 3600
            hour = hours
            // The Pi gives the moon's age for today; it ages a day a day.
            elongation = snapshot.moon?.today.map {
                Orrery.elongation(ageDays: $0.ageDays + (hours - 12) / 24)
            }
            events = Almanac.ring(snapshot, now: now).map {
                max($0.start.timeIntervalSince(midnight), now.timeIntervalSince(midnight)) / 3600
                    ... min($0.end.timeIntervalSince(midnight), now.timeIntervalSince(midnight) + 86_400) / 3600
            }
        }
    }

    let state: State
    var swing: Double

    var animatableData: Double {
        get { swing }
        set { swing = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2
            // Before the swing, each planet is held back round its orbit, the inner ones most.
            func place(_ angle: Double, lag: Double) -> Double { angle - (1 - swing) * lag }
            let planets: [(angle: Double, orbit: CGFloat, size: CGFloat, colour: Color, arm: CGFloat)] = [
                (place(state.mercury, lag: 200), Orbit.mercury, 0.018, Color(red: 0.72, green: 0.68, blue: 0.64), 0.006),
                (place(state.venus, lag: 150), Orbit.venus, 0.026, Color(red: 0.95, green: 0.88, blue: 0.70), 0.007),
                (place(state.mars, lag: 70), Orbit.mars, 0.022, Color(red: 0.86, green: 0.42, blue: 0.28), 0.007),
            ]
            let earthAngle = place(state.earth, lag: 110)
            let e = at(c, r * Orbit.earth, earthAngle)

            // The arms, from the hub out to each planet.
            for p in planets {
                arm(context, centre: c, angle: p.angle, length: r * p.orbit, width: r * p.arm, r: r)
            }
            arm(context, centre: c, angle: earthAngle, length: r * Orbit.earth, width: r * 0.011, r: r)

            // The sun: rays, then a glowing disc.
            var glow = context
            glow.addFilter(.blur(radius: r * 0.04))
            glow.fill(circle(c, r * 0.08), with: .color(Color(red: 1.0, green: 0.78, blue: 0.4).opacity(0.7)))
            // Straight rays between wavy flames, as on an old engraving's sun.
            var rays = Path()
            for k in 0..<16 {
                let a = Double(k) * 22.5
                rays.move(to: at(c, r * 0.07, a - 4))
                if k % 2 == 0 {
                    rays.addLine(to: at(c, r * 0.19, a))
                } else {
                    rays.addQuadCurve(to: at(c, r * 0.12, a + 3), control: at(c, r * 0.095, a - 6))
                    rays.addQuadCurve(to: at(c, r * 0.165, a - 1), control: at(c, r * 0.145, a + 7))
                    rays.addQuadCurve(to: at(c, r * 0.07, a + 4), control: at(c, r * 0.11, a + 5))
                }
                rays.addLine(to: at(c, r * 0.07, a + 4))
            }
            // Over the glow and out past the wheel's teeth, edged dark so they hold against the brass.
            context.stroke(rays, with: .color(.black.opacity(0.75)), lineWidth: 2.5)
            context.fill(rays, with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.75), Color(red: 1, green: 0.76, blue: 0.35)]),
                                                     center: c, startRadius: r * 0.07, endRadius: r * 0.19))
            context.fill(circle(c, r * 0.072), with: .radialGradient(
                Gradient(colors: [Color(red: 1, green: 0.98, blue: 0.88), Color(red: 1, green: 0.8, blue: 0.4),
                                  Color(red: 0.85, green: 0.55, blue: 0.2)]),
                center: c, startRadius: 0, endRadius: r * 0.072))

            for p in planets {
                let spot = at(c, r * p.orbit, p.angle)
                context.stroke(circle(spot, r * p.size * 1.45), with: .color(Ink.brass.opacity(0.85)), lineWidth: 1.5)
                sphere(context, at: spot, radius: r * p.size, colour: p.colour, sun: c)
            }

            // Round the earth: the moon's orbit, the day ring with its events and its hand.
            let toSun = earthAngle + 180
            context.stroke(circle(e, r * Orbit.moon), with: .color(Ink.ivory.opacity(0.28)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
            context.stroke(circle(e, r * Orbit.day), with: .color(Ink.brass.opacity(0.8)), lineWidth: 2)
            context.stroke(circle(e, r * (Orbit.day + 0.02)), with: .color(Ink.brass.opacity(0.55)), lineWidth: 1)
            func onRing(_ hour: Double) -> Double { toSun + (hour - 12) / 24 * 360 }
            var hours = Path()
            for h in 0..<24 {
                let a = onRing(Double(h))
                hours.move(to: at(e, r * Orbit.day, a))
                hours.addLine(to: at(e, r * (Orbit.day + (h % 6 == 0 ? 0.02 : 0.01)), a))
            }
            context.stroke(hours, with: .color(Ink.brass.opacity(0.8)), lineWidth: 1.5)
            for (i, span) in state.events.enumerated() where span.upperBound > span.lowerBound {
                var arc = Path()
                arc.addArc(center: e, radius: r * Orbit.day, startAngle: .degrees(-onRing(span.lowerBound)),
                           endAngle: .degrees(-onRing(span.upperBound)), clockwise: true)
                context.stroke(arc, with: .color(Ink.events[i % Ink.events.count]),
                               style: StrokeStyle(lineWidth: r * 0.02, lineCap: .round))
            }
            // Noon faces the sun.
            context.fill(circle(at(e, r * (Orbit.day + 0.034), toSun), r * 0.008), with: .color(Color(red: 1, green: 0.8, blue: 0.4)))
            context.stroke(circle(e, r * 0.042 * 1.3), with: .color(Ink.brass.opacity(0.85)), lineWidth: 1.5)
            sphere(context, at: e, radius: r * 0.042, colour: Color(red: 0.32, green: 0.56, blue: 0.82), sun: c)
            var hand = Path()
            let handAngle = onRing(state.hour) - (1 - swing) * 240
            hand.move(to: e)
            hand.addLine(to: at(e, r * (Orbit.day + 0.03), handAngle))
            context.stroke(hand, with: .color(Ink.ivory), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            context.fill(circle(at(e, r * (Orbit.day + 0.03), handAngle), r * 0.007), with: .color(Ink.ivory))

            if let elongation = state.elongation {
                let m = at(e, r * Orbit.moon, toSun + elongation - (1 - swing) * 300)
                sphere(context, at: m, radius: r * 0.02, colour: Color(red: 0.9, green: 0.89, blue: 0.86), sun: c)
            }
        }
    }

    /// A brass arm from the hub, tapering to its planet, with a bead and a pierced lozenge
    /// along it and a counterweight on the hub's far side.
    private func arm(_ context: GraphicsContext, centre c: CGPoint, angle: Double, length: CGFloat, width: CGFloat, r: CGFloat) {
        let tip = at(c, length, angle)
        // Out past the sun's rays, so it shows.
        let tail = at(c, r * 0.155, angle + 180)
        func side(_ distance: CGFloat, _ half: CGFloat) -> (CGPoint, CGPoint) {
            let p = at(c, distance, angle)
            return (at(p, half, angle + 90), at(p, half, angle - 90))
        }
        let (rootL, rootR) = side(0, width * 0.9)
        let (tipL, tipR) = side(length, width * 0.4)
        var body = Path()
        body.move(to: rootL)
        body.addLine(to: tipL)
        body.addLine(to: tipR)
        body.addLine(to: rootR)
        body.closeSubpath()
        let shade = GraphicsContext.Shading.linearGradient(Gradient(colors: [Color(red: 0.98, green: 0.86, blue: 0.5), Ink.deepBrass]),
                                                           startPoint: c, endPoint: tip)
        context.fill(body, with: shade)

        // The counterweight, on a short stub behind the hub.
        var stub = Path()
        stub.move(to: c)
        stub.addLine(to: tail)
        context.stroke(stub, with: .color(Ink.deepBrass), style: StrokeStyle(lineWidth: width * 0.8, lineCap: .round))
        context.fill(circle(tail, max(width * 1.6, r * 0.012)), with: .radialGradient(
            Gradient(colors: [Color(red: 0.98, green: 0.88, blue: 0.58), Ink.deepBrass]),
            center: tail, startRadius: 0, endRadius: max(width * 1.6, r * 0.012)))

        // A bead a third of the way out, and a pierced lozenge beyond it on the longer arms.
        context.fill(circle(at(c, length * 0.33, angle), width * 1.3), with: shade)
        if length > r * 0.25 {
            let mid = at(c, length * 0.62, angle)
            let along = length * 0.07
            var lozenge = Path()
            lozenge.move(to: at(mid, along, angle))
            lozenge.addLine(to: at(mid, width * 1.6, angle + 90))
            lozenge.addLine(to: at(mid, along, angle + 180))
            lozenge.addLine(to: at(mid, width * 1.6, angle - 90))
            lozenge.closeSubpath()
            // Pierced: the plate's black shows through, inside a brass frame.
            context.fill(lozenge, with: .color(.black))
            context.stroke(lozenge, with: shade, lineWidth: max(1.5, width * 0.5))
        }
    }

    /// A ball lit from the sun: bright on its sunward side, falling to near black away from it.
    private func sphere(_ context: GraphicsContext, at p: CGPoint, radius: CGFloat, colour: Color, sun: CGPoint) {
        let dx = sun.x - p.x, dy = sun.y - p.y
        let length = max(sqrt(dx * dx + dy * dy), 0.001)
        let lit = CGPoint(x: p.x + dx / length * radius * 0.45, y: p.y + dy / length * radius * 0.45)
        context.fill(circle(p, radius), with: .radialGradient(
            Gradient(stops: [.init(color: .white.opacity(0.9), location: 0), .init(color: colour, location: 0.25),
                             .init(color: colour.opacity(0.35), location: 0.75), .init(color: .black, location: 1)]),
            center: lit, startRadius: 0, endRadius: radius * 1.5))
    }
}

// MARK: - The almanac

private struct Almanac: View {
    let snapshot: Snapshot
    let now: Date
    /// The build-in's progress, 0 to 1: the sections rise in one after another.
    let rise: Double

    /// The events on the earth's day ring: timed ones still to finish in the next 24 hours, at
    /// most four.
    static func ring(_ snapshot: Snapshot, now: Date) -> [CalendarEvent] {
        (snapshot.sources.events?.data ?? [])
            .filter { !$0.isAllDay && $0.end > now && $0.start < now.addingTimeInterval(86_400) }
            .sorted { $0.start < $1.start }
            .prefix(4)
            .map { $0 }
    }

    var body: some View {
        let zone = snapshot.timeZone
        let clock = ClockTime.parts(now, in: zone)
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 0) {
                Text(now.formatted(Date.FormatStyle(timeZone: zone).weekday(.wide).day().month(.wide)).uppercased())
                    .font(Face.engraved(28))
                    .tracking(28 * 0.12)
                    .foregroundStyle(Ink.brass)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(clock.time)
                        .font(Face.serif(136, .light))
                        .monospacedDigit()
                        .foregroundStyle(Ink.ivory)
                    if let period = clock.period {
                        Text(period)
                            .font(Face.serif(40, .light))
                            .foregroundStyle(Ink.soft)
                    }
                }
            }
            .rise(rise, index: 0)
            if let lines = sun { section("Sun", lines).rise(rise, index: 1) }
            if let lines = moon { section("Moon", lines).rise(rise, index: 2) }
            section("Season", [season]).rise(rise, index: 3)
            events.rise(rise, index: 4)
        }
    }

    private func section(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(Face.engraved(22))
                .tracking(22 * 0.2)
                .foregroundStyle(Ink.brass.opacity(0.85))
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(Face.serif(30))
                    .foregroundStyle(Ink.soft)
            }
        }
    }

    /// "Rises 7:14a · sets 6:31p", and "11h 17m of daylight, 2 min less tomorrow".
    private var sun: [String]? {
        let zone = snapshot.timeZone
        let model = SunModel(snapshot: snapshot)
        guard let (rise, set) = LightCycle.daylight(snapshot, sun: model, on: CivilDate(now, in: zone)) else { return nil }
        var lines = ["Rises \(CompactTime.string(rise, in: zone)) · sets \(CompactTime.string(set, in: zone))"]
        if let light = Orrery.daylight(snapshot, now: now) {
            var line = "\(LightCycle.formatLength(light.length)) of daylight"
            if let change = light.change, abs(change) >= 30 {
                let minutes = Int((abs(change) / 60).rounded())
                line += ", \(minutes) min \(change < 0 ? "less" : "more") tomorrow"
            }
            lines.append(line)
        }
        return lines
    }

    /// "Waxing crescent, 18% lit", and "Full in 10 days · rises 11:26a".
    private var moon: [String]? {
        guard let moon = snapshot.moon, let day = moon.today else { return nil }
        let zone = snapshot.timeZone
        var next = "\(moon.next.isFull ? "Full" : "New") \(moon.next.days == 0 ? "today" : moon.next.days == 1 ? "tomorrow" : "in \(moon.next.days) days")"
        if moon.supermoon { next += ", a supermoon" }
        if let rise = moon.rise { next += " · rises \(CompactTime.string(rise, in: zone))" }
        return ["\(moon.phaseName), \(Int(day.illumination.rounded()))% lit", next]
    }

    /// "Winter solstice in 66 days".
    private var season: String {
        let zone = snapshot.timeZone
        let next = Orrery.nextTurning(after: now)
        let name = next.turning.name(southern: Orrery.isSouthern(snapshot, now: now) ?? false)
        let days = Orrery.days(from: now, to: next.date, in: zone)
        return days == 0 ? "\(name) today" : days == 1 ? "\(name) tomorrow" : "\(name) in \(days) days"
    }

    /// The events on the ring, each with its enamel's dot.
    private var events: some View {
        let zone = snapshot.timeZone
        let ring = Self.ring(snapshot, now: now)
        return VStack(alignment: .leading, spacing: 12) {
            Text("NEXT 24 HOURS")
                .font(Face.engraved(22))
                .tracking(22 * 0.2)
                .foregroundStyle(Ink.brass.opacity(0.85))
            if ring.isEmpty {
                Text("Nothing on the calendar")
                    .font(Face.serif(30))
                    .foregroundStyle(Ink.faint)
            }
            ForEach(Array(ring.enumerated()), id: \.element) { i, event in
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Circle()
                        .fill(Ink.events[i % Ink.events.count])
                        .frame(width: 14, height: 14)
                    Text(event.start <= now ? "Now" : Skylight.when(event, now: now, zone: zone))
                        .font(Face.serif(26))
                        .monospacedDigit()
                        .foregroundStyle(Ink.faint)
                        .fixedSize()
                    Text(event.summary)
                        .font(Face.serif(30))
                        .foregroundStyle(Ink.ivory)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
