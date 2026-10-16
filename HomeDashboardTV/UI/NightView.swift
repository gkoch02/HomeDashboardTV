import DashboardCore
import SwiftUI

/// The Pi's `wide_night` theme, for after dark: four marks and nothing else (the moon's
/// phase, the temperature, the air-quality index and the sky), spaced evenly across the
/// screen's midline, each with a tracked label beneath.
///
/// The panel's red ground would light a dark room, so this is its inverse,
/// `wide_night_invert`: dim red marks on black. The moon is its lit part alone, with no
/// outline on the dark limb, and is spaced by that part, as on the panel. A mark
/// without data is dropped and the rest re-spaced; every mark shares one height, the
/// tallest at which the row fits.
///
/// The marks strike up as the layout appears, like an old display's tubes: each, left to
/// right, throws a few stray flashes and a weak flutter before it holds, with a brief bloom,
/// and its label catches after it.
struct NightView: Theme {
    let snapshot: Snapshot
    let now: Date

    @State private var phase = Ignition.dark

    var body: some View {
        // The timeline runs only while the marks strike: at rest the screen stays still.
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !phase.isStriking)) { context in
            let t = phase.elapsed(at: context.date)
            GeometryReader { geometry in
                let cap = geometry.size.height * 0.42
                ViewThatFits(in: .horizontal) {
                    ForEach([1.0, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4], id: \.self) { scale in
                        row(height: cap * scale, t: t)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .onBuildIn(reset: { settled in phase = settled ? .lit : .dark }) {
            let start = Date.now
            phase = .striking(start)
            DispatchQueue.main.asyncAfter(deadline: .now() + Strike.duration(marks: marks.count)) {
                if phase == .striking(start) { phase = .lit }
            }
        }
    }

    var backdrop: some View { Color.black }

    private enum Mark: Hashable {
        case moon(Double), number(String), sky(String)
    }

    private var marks: [(mark: Mark, label: String)] {
        var out: [(Mark, String)] = []
        if let fraction = snapshot.moon?.today?.fraction { out.append((.moon(fraction), "MOON")) }
        let weather = snapshot.sources.weather?.data
        if let weather { out.append((.number("\(Int(weather.currentTemp.rounded()))°"), "TEMP")) }
        if let aqi = snapshot.sources.airQuality?.data?.aqi { out.append((.number("\(aqi)"), "AQI")) }
        if let weather { out.append((.sky(WeatherSymbol.name(for: weather.currentIcon)), "SKY")) }
        return out
    }

    /// The marks at *height*, with gaps of at least half that between them and at the ends.
    /// *t* is the time since the marks began to strike.
    private func row(height: CGFloat, t: Double) -> some View {
        let gap = max(48, height * 0.5)
        return HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: gap)
            ForEach(Array(marks.enumerated()), id: \.element.label) { index, item in
                VStack(spacing: 34) {
                    mark(item.mark, height: height)
                        .frame(height: height)
                        .struck(Strike.mark(index), at: t, bloom: height * 0.12)
                    Text(item.label)
                        .font(.custom(Face.label, size: 28).weight(.heavy))
                        .tracking(28 * 0.4)
                        .foregroundStyle(Ink.mark.opacity(0.85))
                        .struck(Strike.label(index), at: t, bloom: 8)
                }
                .fixedSize()
                Spacer(minLength: gap)
            }
        }
    }

    @ViewBuilder private func mark(_ mark: Mark, height: CGFloat) -> some View {
        switch mark {
        case .moon(let fraction):
            // The row spaces the lit part, not the whole disc, so the gaps read even: the
            // terminator meets the midline at cos(2πf) of the radius, so a gibbous moon's lit
            // part spans (1 − cos 2πf) of it, on the right while waxing. A crescent's horns
            // reach back to the centre line, so it spans at least the half disc.
            let lit = max((1 - cos(2 * .pi * fraction)) / 2, 0.5) * height
            LitShape(fraction: fraction)
                .fill(Ink.mark)
                .frame(width: height, height: height)
                .frame(width: lit, alignment: fraction.truncatingRemainder(dividingBy: 1) < 0.5 ? .trailing : .leading)
        case .number(let text):
            // Jura's figures stand 0.633 of the size, and sit 0.057 of it below the
            // line box's centre: sized and lifted so the digits alone span the height.
            let size = height / 0.633
            Text(text)
                .font(.custom(Face.numeral, size: size).weight(.semibold))
                .foregroundStyle(Ink.mark)
                .offset(y: -0.057 * size)
                .frame(height: height)
        case .sky(let symbol):
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .fontWeight(.medium)
                .foregroundStyle(Ink.mark)
                .frame(height: height)
        }
    }
}

// MARK: - The strike

/// Where the build-in is: dark before it, striking from a moment, lit at rest.
private enum Ignition: Equatable {
    case dark, striking(Date), lit

    var isStriking: Bool {
        if case .striking = self { true } else { false }
    }

    /// Seconds since the strike began: before every mark when dark, after all of them when lit.
    func elapsed(at date: Date) -> Double {
        switch self {
        case .dark: -1
        case .striking(let start): date.timeIntervalSince(start)
        case .lit: .infinity
        }
    }
}

/// One mark's strike, as a tube catches: a few stray flashes, a weak flutter, a beat of dark,
/// then on for good. Random, but the same every time: seeded by the mark's place.
private struct Strike {
    /// Brightness from each time on, until the next step.
    private(set) var steps: [(t: Double, level: Double)] = []
    /// When it comes on for good.
    private(set) var settle: Double = 0

    /// The *index*th mark from the left: a beat after the one before.
    static func mark(_ index: Int) -> Strike {
        Strike(seed: UInt64(index) &+ 0x51, delay: 0.25 + 0.34 * Double(index), flashes: 3, flutter: true)
    }

    /// The *index*th label: a quick catch just after its mark holds.
    static func label(_ index: Int) -> Strike {
        Strike(seed: UInt64(index) &+ 0xA7, delay: mark(index).settle + 0.08, flashes: 1, flutter: false)
    }

    /// How long a row of *marks* takes to strike and the last bloom to fade.
    static func duration(marks: Int) -> Double {
        (0..<max(marks, 1)).map { label($0).settle }.max()! + Self.bloomFade * 3
    }

    /// The bloom's time constant once a mark holds.
    static let bloomFade = 0.22

    private init(seed: UInt64, delay: Double, flashes: Int, flutter: Bool) {
        var random = SplitMix(seed: seed)
        var t = delay + 0.1 * random.unit()
        for _ in 0..<flashes {
            steps.append((t, 0.55 + 0.45 * random.unit()))
            t += 0.025 + 0.05 * random.unit()
            steps.append((t, 0))
            t += 0.05 + 0.16 * random.unit()
        }
        if flutter {
            for level in [0.22, 0.4, 0.15, 0.32] {
                steps.append((t, level))
                t += 0.035 + 0.035 * random.unit()
            }
            steps.append((t, 0))
            t += 0.06 + 0.08 * random.unit()
        }
        settle = t
    }

    /// The mark's brightness at *t*, 0 to 1.
    func level(at t: Double) -> Double {
        if t >= settle { return 1 }
        return steps.last { $0.t <= t }?.level ?? 0
    }

    /// The glow round it at *t*: with each flash, and a bloom as it holds that dies away.
    func bloom(at t: Double) -> Double {
        t >= settle ? exp(-(t - settle) / Self.bloomFade) : level(at: t) * 0.6
    }
}

extension View {
    /// Lights the view as *strike* has it at *t*: its brightness, a red bloom of up to
    /// *bloom* points, and a sideways jitter of a point or two while it flashes.
    fileprivate func struck(_ strike: Strike, at t: Double, bloom radius: CGFloat) -> some View {
        let level = strike.level(at: t)
        let bloom = strike.bloom(at: t)
        let flashing = t < strike.settle && level > 0
        return self
            .opacity(level)
            .shadow(color: Ink.mark.opacity(bloom), radius: radius * bloom)
            .offset(x: flashing ? 2.5 * sin(t * 211) : 0)
    }
}

private enum Ink {
    /// Dim enough to leave a dark room dark.
    static let mark = Color(red: 0.78, green: 0.13, blue: 0.10)
}

private enum Face {
    static let numeral = "Jura-Light"
    static let label = "Oxanium-ExtraLight"
}
