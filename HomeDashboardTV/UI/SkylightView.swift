import DashboardCore
import SwiftUI

/// A layout drawn for the TV rather than ported from the Pi: the sky outside, live, over a
/// black ground, with the day set in the dark around it.
///
/// The sky is a Metal shader running at 30 frames a second (`SkylightSky.metal`, drawn by
/// `SkyLayer`, so on an HDR output the sun, the stars and the lightning pass white): coloured by
/// the sun's altitude now, with the sun where it is between sunrise and sunset, stars that
/// twinkle after dark, and the current weather as moving cloud, rain, snow, fog or lightning,
/// drifting with the real wind. The moon rides it at tonight's phase. Below two ridges the
/// ground is true black, which an OLED draws with its pixels off, and the text there glows.
///
/// Over the sky: the time and the agenda still to come on the left, the weather now on the
/// right. On the ground: the next 24 hours as a temperature line coloured by the heat, and
/// the days ahead beside the sun and moon times.
///
/// As the layout appears the sky comes up out of the black like a dawn and the sun or moon
/// rises into place; the clock, the weather and the agenda rise in over it, and the next 24
/// hours draw themselves across the ground.
struct SkylightView: Theme {
    let snapshot: Snapshot
    let now: Date

    @State private var build = SkylightBuild.start

    private var zone: TimeZone { snapshot.timeZone }

    /// The sky runs to every edge; the text keeps its own overscan-safe margins.
    static let fullBleed = true

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let ground = size.height * Layout.horizon
            ZStack(alignment: .topLeading) {
                HStack(alignment: .top, spacing: 60) {
                    VStack(alignment: .leading, spacing: 0) {
                        ClockBlock(now: now, zone: zone)
                            .opacity(build.clock)
                            .offset(y: (1 - build.clock) * 20)
                        UpNext(snapshot: snapshot, now: now, rise: build.agenda)
                            .padding(.top, 26)
                    }
                    .frame(maxWidth: size.width * 0.44, alignment: .leading)
                    Spacer(minLength: 0)
                    if let weather = snapshot.sources.weather?.data {
                        WeatherNow(weather: weather, air: snapshot.sources.airQuality?.data,
                                   isMetric: snapshot.isMetric)
                            .opacity(build.weather)
                            .offset(y: (1 - build.weather) * 20)
                    }
                }
                .padding(.horizontal, Layout.marginH)
                .padding(.top, Layout.marginTop)
                .frame(width: size.width, height: ground - 70, alignment: .topLeading)

                VStack(spacing: 26) {
                    if let weather = snapshot.sources.weather?.data {
                        Ribbon(points: Skylight.ribbon(weather, now: now),
                               sunTimes: Skylight.sunTimes(snapshot, now: now),
                               isMetric: snapshot.isMetric, zone: zone)
                            .frame(height: 224)
                            .wipe(build.ribbon, softness: 0.25)
                    }
                    HStack(alignment: .bottom, spacing: 50) {
                        if let weather = snapshot.sources.weather?.data {
                            Outlook(days: Skylight.outlook(weather, now: now, zone: zone, count: 6),
                                    now: now, zone: zone, isMetric: snapshot.isMetric)
                        }
                        Spacer(minLength: 0)
                        SunAndMoon(snapshot: snapshot, now: now)
                    }
                    .opacity(build.ground)
                    .offset(y: (1 - build.ground) * 20)
                }
                .padding(.horizontal, Layout.marginH)
                .padding(.bottom, Layout.marginBottom)
                .frame(width: size.width, height: size.height - ground - 18, alignment: .bottom)
                .offset(y: ground + 18)
            }
        }
        // After the sky has begun to lighten (SkyBackdrop's own build-in).
        .onBuildIn(reset: { settled in build = settled ? .settled : .start }) {
            withAnimation(.easeOut(duration: 0.8).delay(0.7)) { build.clock = 1 }
            withAnimation(.easeOut(duration: 0.8).delay(0.9)) { build.weather = 1 }
            withAnimation(.linear(duration: 1.3).delay(1.0)) { build.agenda = 1 }
            withAnimation(.easeInOut(duration: 1.6).delay(1.2)) { build.ribbon = 1 }
            withAnimation(.easeOut(duration: 0.8).delay(1.8)) { build.ground = 1 }
        }
    }

    var backdrop: some View { SkyBackdrop(snapshot: snapshot, now: now) }

    func notice(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.arrow.circlepath")
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(Ink.amber)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.black.opacity(0.55), in: Capsule())
    }
}

/// How far the text's build-in has got, each part 0 to 1.
private struct SkylightBuild {
    var clock: Double
    var weather: Double
    var agenda: Double
    var ribbon: Double
    var ground: Double

    static let start = SkylightBuild(clock: 0, weather: 0, agenda: 0, ribbon: 0, ground: 0)
    static let settled = SkylightBuild(clock: 1, weather: 1, agenda: 1, ribbon: 1, ground: 1)
}

private enum Layout {
    /// Where the ground starts, as a share of the height.
    static let horizon: CGFloat = 0.6
    /// tvOS's overscan-safe insets, which the text keeps.
    static let marginH: CGFloat = 90
    static let marginTop: CGFloat = 54
    static let marginBottom: CGFloat = 50
}

private enum Ink {
    static let text = Color(red: 0.97, green: 0.97, blue: 0.98)
    static let soft = text.opacity(0.72)
    static let faint = text.opacity(0.46)
    static let amber = Color.p3(1.0, 0.76, 0.32)
    static let now = Color.p3(1.0, 0.62, 0.36)
    static let rain = Color.p3(0.45, 0.72, 1.0)
}

// MARK: - The sky

/// The shader sky, the moon over it and the black ground, behind the drifting text. The
/// sky's colours change with the minute; its motion runs on its own timeline, so only this
/// layer redraws thirty times a second.
private struct SkyBackdrop: View {
    let snapshot: Snapshot
    let now: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(DashboardStore.self) private var store
    @State private var clock = SkyClock()
    @State private var dawn = Dawn.dark
    @State private var moonRise = 0.0

    var body: some View {
        let sky = Skylight.sky(snapshot, now: now)
        let palette = Palette(sky: sky)
        let moon = Skylight.moon(snapshot, now: now)
        GeometryReader { geometry in
            let size = geometry.size
            let ground = size.height * Layout.horizon
            let sun = sunPlace(sky, size: size, ground: ground)
            let drift = BurnIn.drift(at: now)
            ZStack(alignment: .topLeading) {
                SkyLayer(fragment: "skylightSky", paused: reduceMotion, highlights: store.highlights) { frame in
                    let motion = clock.advance(to: frame.date, drift: sky.drift)
                    let rise = dawn.rise(at: frame.date)
                    let risen = (centre: CGPoint(x: sun.centre.x, y: sun.centre.y + (1 - rise) * Dawn.climb),
                                 shown: sun.shown * rise)
                    return SkylightUniforms(
                        frame: frame.header(time: motion.time),
                        clouds: motion.clouds, rain: motion.rain, snow: motion.snow,
                        zenith: Sky.rgb(palette.zenith), horizon: Sky.rgb(palette.horizon), glow: Sky.rgb(palette.glow),
                        sun: SIMD4(Float(risen.centre.x), Float(risen.centre.y), Float(sun.radius), Float(risen.shown)),
                        light: SIMD4(Float(palette.glowStrength), Float(palette.twilight), Float(palette.stars),
                                     sky.precip == .storm ? 1 : 0),
                        weather: SIMD4(Float(sky.cover), sky.precip == .rain || sky.precip == .storm ? Float(sky.intensity) : 0,
                                       sky.precip == .snow ? Float(sky.intensity) : 0, sky.precip == .fog ? 0.55 : 0),
                        cloudLit: Sky.rgb(palette.cloudLit), cloudShade: Sky.rgb(palette.cloudShade),
                        ground: SIMD4(Float(ground), frame.headroom, Float(dawn.light(at: frame.date)), 0),
                        motion: SIMD4(Float(sky.drift), 0, Float(drift.width), Float(drift.height)))
                }
                if let moon, !sky.hidesBodies {
                    // The moon is drawn here, not in the timeline, so it rises by animation.
                    let radius: CGFloat = 46
                    let x = size.width * SkyPath.x(moon.path)
                    let rise = sin(.pi * min(max(moon.path, 0), 1))
                    let y = ground - 60 - CGFloat(rise) * (ground * 0.58)
                    MoonDisc(fraction: moon.fraction, radius: radius, halo: sky.isNight)
                        // By day the photograph's dark side would sit on the blue as a black
                        // disc; screened, only the lit side shows, as the moon does by day.
                        .blendMode(sky.isNight ? .normal : .screen)
                        .opacity((sky.isNight ? 1 : 0.7) * (1 - 0.55 * sky.cover) * moonRise)
                        .position(x: x, y: y + (1 - moonRise) * Dawn.climb)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .background(Color.black)
        .onBuildIn(reset: { settled in
            dawn = settled ? .day : .dark
            moonRise = settled ? 1 : 0
        }) {
            dawn = .breaking(.now)
            withAnimation(.easeOut(duration: 1.4).delay(0.6)) { moonRise = 1 }
        }
    }

    /// The sun's centre, radius and how much shows: across the open middle of the sky from left
    /// (sunrise) to right (sunset), as high as its altitude, sinking out of sight at the horizon.
    private func sunPlace(_ sky: Skylight.Sky, size: CGSize, ground: CGFloat) -> (centre: CGPoint, radius: CGFloat, shown: Double) {
        let path = min(max(sky.sunPath, -0.08), 1.08)
        let height = min(max(sky.altitude, -12), 62) / 62
        let x = size.width * SkyPath.x(path)
        let y = ground - 30 - CGFloat(height) * (ground - 150)
        let up = min(max((sky.altitude + 1) / 3, 0), 1)
        return (CGPoint(x: x, y: y), 24, sky.hidesBodies ? 0 : up * (1 - 0.6 * sky.cover))
    }
}

/// The sky's build-in, timed by the sky's own timeline (its shader's inputs do not animate):
/// it lightens out of the black, and the sun climbs into its place a beat behind.
private enum Dawn: Equatable {
    case dark, breaking(Date), day

    /// How far the sun climbs in from below its place.
    static let climb: CGFloat = 70

    /// How light the sky is, 0 (black) to 1.
    func light(at date: Date) -> Double { eased(at: date, from: 0, over: 1.8) }

    /// How far the sun has climbed, 0 to 1.
    func rise(at date: Date) -> Double { eased(at: date, from: 0.6, over: 1.4) }

    private func eased(at date: Date, from delay: Double, over duration: Double) -> Double {
        switch self {
        case .dark: return 0
        case .day: return 1
        case .breaking(let start):
            let t = min(max((date.timeIntervalSince(start) - delay) / duration, 0), 1)
            return 1 - pow(1 - t, 3)
        }
    }
}

/// The sky's motion, summed frame by frame in doubles: how far the cloud has drifted and
/// changed shape, and how far each layer of rain and snow has fallen. Summing, rather than
/// multiplying the time by the wind, means a new wind changes the cloud's speed and never
/// jumps it to another place. The falls fold at 1024 cells, as the shader's ids do, and the
/// cyclic clock at an hour, so nothing in the sky ever jumps; the cloud's sums stay small
/// enough for the shader's floats over weeks.
private final class SkyClock {
    private var last: Date?
    private var cloud = 0.0, evolve = 0.0
    private var rain = [0.0, 0.0, 0.0], snow = [0.0, 0.0, 0.0], carry = 0.0

    func advance(to date: Date, drift: Double) -> (time: Float, clouds: SIMD4<Float>, rain: SIMD4<Float>, snow: SIMD4<Float>) {
        // A gap (the app in the background, a paused timeline) resumes from where it stopped.
        let dt = last.map { min(max(date.timeIntervalSince($0), 0), 0.25) } ?? 0
        last = date
        cloud += dt * drift * 0.007
        evolve += dt
        for layer in 0..<3 {
            let s = 1 + Double(layer) * 0.7
            rain[layer] = (rain[layer] + dt * (13 + 3 * Double(layer)) / s).truncatingRemainder(dividingBy: 1024)
            snow[layer] = (snow[layer] + dt * (0.32 + 0.14 * Double(layer))).truncatingRemainder(dividingBy: 1024)
        }
        carry = (carry + dt * drift * 0.12).truncatingRemainder(dividingBy: 1024)
        let time = Float(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600))
        return (time,
                SIMD4(Float(cloud), Float(evolve * 0.0021), Float(evolve * 0.0013), 0),
                SIMD4(Float(rain[0]), Float(rain[1]), Float(rain[2]), 0),
                SIMD4(Float(snow[0]), Float(snow[1]), Float(snow[2]), Float(carry)))
    }
}

/// `SkylightSky.metal`'s inputs, field for field.
private struct SkylightUniforms {
    var frame, clouds, rain, snow: SIMD4<Float>
    var zenith, horizon, glow: SIMD4<Float>
    var sun, light, weather: SIMD4<Float>
    var cloudLit, cloudShade: SIMD4<Float>
    var ground, motion: SIMD4<Float>
}

/// Where the sun and moon cross the sky: the open middle between the agenda and the weather,
/// so neither ever sits behind text. Rise is on the left, set on the right. The agenda column
/// may run to 44 % of the width past its 90 pt margin, so the moon's left edge (46 pt out from
/// its centre) starts clear of it; the weather's lines start at about 71 %.
private enum SkyPath {
    static func x(_ path: Double) -> CGFloat { CGFloat(0.52 + 0.14 * path) }
}

/// The sky's colours for one moment, from the sun's altitude and the weather.
private struct Palette {
    var zenith: Color
    var horizon: Color
    var glow: Color
    var glowStrength: Double
    var twilight: Double
    var stars: Double
    var cloudLit: Color
    var cloudShade: Color

    init(sky: Skylight.Sky) {
        let alt = sky.altitude
        let day = smooth(-8, 8, alt)
        let golden = exp(-pow((alt - 3) / 8, 2))
        // Overcast dulls everything toward grey; rain and storm darken it.
        let dull = min(1, max(0, (sky.cover - 0.5) / 0.4)) * 0.75 + sky.intensity * 0.2
        let dim = 1 - 0.3 * dull - (sky.precip == .storm ? 0.2 : 0)

        func grey(_ c: RGB, _ amount: Double) -> RGB {
            let l = 0.3 * c.r + 0.59 * c.g + 0.11 * c.b
            return c.mix(RGB(l, l, l), amount)
        }

        let z = grey(Self.zenith(alt), dull * 0.8).scaled(dim)
        let h = grey(RGB(SkyColour.rgb(alt)), dull * 0.7).scaled(dim)
        zenith = z.color
        horizon = h.color

        let warm = RGB(1.0, 0.95, 0.84).mix(RGB(1.0, 0.55, 0.28), golden)
        glow = warm.color
        glowStrength = (0.12 + 0.4 * golden) * smooth(-10, 0, alt) * (1 - 0.7 * dull)
        twilight = 0.8 * exp(-pow((alt + 1) / 6.5, 2)) * (1 - 0.6 * dull)
        stars = (1 - smooth(-14, -6, alt)) * (1 - sky.cover * 0.9)

        // Cloud by day is white, warmed near the horizon hours and greyed under overcast; by
        // night it is a dim grey just above the sky, lit by the town below.
        let dayLit = RGB(0.98, 0.97, 0.96).mix(RGB(1.0, 0.72, 0.5), golden * 0.7)
        let nightLit = RGB(0.15, 0.15, 0.19)
        let lit = nightLit.mix(dayLit, day).mix(RGB(0.6, 0.62, 0.66).scaled(0.4 + 0.6 * day), dull * 0.7).scaled(dim)
        let shadeTint = RGB(0.58, 0.6, 0.7).mix(RGB(0.55, 0.42, 0.5), golden * 0.6)
        cloudLit = lit.color
        cloudShade = RGB(lit.r * shadeTint.r, lit.g * shadeTint.g, lit.b * shadeTint.b).scaled(0.95).color
    }

    /// The top of the sky for the sun's altitude: deeper than the horizon, black at night.
    static func zenith(_ alt: Double) -> RGB {
        let stops: [(Double, RGB)] = [
            (30, RGB(0.05, 0.22, 0.52)),
            (10, RGB(0.11, 0.31, 0.64)),
            (0, RGB(0.15, 0.25, 0.5)),
            (-4, RGB(0.11, 0.14, 0.34)),
            (-8, RGB(0.05, 0.06, 0.18)),
            (-14, RGB(0.012, 0.016, 0.05)),
            (-90, RGB(0.0, 0.0, 0.008)),
        ]
        if alt >= stops[0].0 { return stops[0].1 }
        for (a, b) in zip(stops, stops.dropFirst()) where alt >= b.0 {
            return b.1.mix(a.1, (alt - b.0) / (a.0 - b.0))
        }
        return stops[stops.count - 1].1
    }
}

private func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = min(max((x - a) / (b - a), 0), 1)
    return t * t * (3 - 2 * t)
}

private struct RGB {
    var r, g, b: Double

    init(_ r: Double, _ g: Double, _ b: Double) { (self.r, self.g, self.b) = (r, g, b) }
    init(_ c: (Double, Double, Double)) { (r, g, b) = c }

    func mix(_ o: RGB, _ t: Double) -> RGB { RGB(r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t) }
    func scaled(_ k: Double) -> RGB { RGB(r * k, g * k, b * k) }
    var color: Color { Color.p3(r, g, b) }
}

// MARK: - Over the sky

private struct ClockBlock: View {
    let now: Date
    let zone: TimeZone

    var body: some View {
        let clock = ClockTime.parts(now, in: zone)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(clock.time)
                    .font(.system(size: 176, weight: .ultraLight))
                    .monospacedDigit()
                    .kerning(-3)
                if let period = clock.period {
                    Text(period)
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(Ink.soft)
                }
            }
            .foregroundStyle(Ink.text)
            Text(now.formatted(Date.FormatStyle(timeZone: zone).weekday(.wide).month(.wide).day()))
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(Ink.soft)
                .padding(.top, -8)
        }
    }
}

/// Today's all-day events and birthdays, then the timed events still to finish today and
/// tomorrow, the one under way first, with when each is.
private struct UpNext: View {
    let snapshot: Snapshot
    let now: Date
    /// The build-in's progress, 0 to 1: the lines rise in one after another.
    let rise: Double

    private var zone: TimeZone { snapshot.timeZone }

    var body: some View {
        let chips = Skylight.allDay(snapshot, now: now).map(\.summary) + birthdays
        let events = Skylight.upNext(snapshot, now: now, limit: chips.isEmpty ? 5 : 4)
        VStack(alignment: .leading, spacing: 18) {
            if !chips.isEmpty {
                // As many whole chips as fit the column, never one cut short.
                ViewThatFits(in: .horizontal) {
                    ForEach((1...min(chips.count, 3)).reversed(), id: \.self) { count in
                        chipRow(Array(chips.prefix(count)))
                    }
                }
                .rise(rise, index: 0)
            }
            if events.isEmpty {
                Text("Nothing else on the calendar")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(Ink.faint)
                    .rise(rise, index: 1)
            }
            ForEach(Array(events.enumerated()), id: \.element) { index, event in
                row(event)
                    .rise(rise, index: index + 1)
            }
        }
    }

    private func chipRow(_ chips: [String]) -> some View {
        HStack(spacing: 12) {
            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                Text(chip)
                    .font(.system(size: 24, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(Ink.text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Ink.text.opacity(0.14), in: Capsule())
            }
        }
    }

    /// Today's birthdays and the next week's, by first name and day.
    private var birthdays: [String] {
        let today = CivilDate(now, in: zone)
        return Agenda.upcomingBirthdays(from: snapshot, now: now)
            .filter { $0.date <= today.adding(days: 6) }
            .map { birthday in
                let when = birthday.date == today ? "today"
                    : birthday.date == today.adding(days: 1) ? "tomorrow"
                    : "on " + birthday.date.start(in: zone).formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated))
                return "🎂 \(birthday.name) \(when)"
            }
    }

    /// One line: when, in the event's colour (warm while it is on), then what and where.
    private func row(_ event: CalendarEvent) -> some View {
        let live = event.start <= now
        let when = live ? "Now – \(CompactTime.string(event.end, in: zone))" : Skylight.when(event, now: now, zone: zone)
        return HStack(alignment: .firstTextBaseline, spacing: 22) {
            Text(when)
                .font(.system(size: 27, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(live ? Ink.now : Ink.soft)
                .frame(width: 232, alignment: .leading)
            Text(event.summary)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Ink.text)
                .lineLimit(1)
                .layoutPriority(1)
            if let place = event.shortLocation {
                Text(place)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(Ink.faint)
                    .lineLimit(1)
            }
        }
    }
}

/// The weather now, set against the right of the sky.
private struct WeatherNow: View {
    let weather: Weather
    let air: AirQuality?
    let isMetric: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(alignment: .center, spacing: 26) {
                Image(systemName: WeatherSymbol.name(for: weather.currentIcon))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 84, weight: .regular))
                Text("\(Int(weather.currentTemp.rounded()))°")
                    .font(.system(size: 176, weight: .ultraLight))
                    .monospacedDigit()
                    .kerning(-3)
                    .foregroundStyle(Ink.text)
            }
            Text(weather.currentDescription.capitalized(with: .current))
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(Ink.text)
                .padding(.top, -10)
            Text("H \(Int(weather.high.rounded()))°   L \(Int(weather.low.rounded()))°")
                .font(.system(size: 32, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(Ink.soft)
            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 28) {
                    if let feels = weather.feelsLike {
                        detail("thermometer.medium", "Feels \(Int(feels.rounded()))°")
                    }
                    if let speed = weather.windSpeed {
                        let compass = weather.windDeg.map { " " + Compass.point($0) } ?? ""
                        detail("wind", "\(Int(speed.rounded())) \(isMetric ? "m/s" : "mph")\(compass)")
                    }
                    detail("humidity", "\(weather.humidity)%")
                }
                HStack(spacing: 28) {
                    if let uv = weather.uvIndex {
                        detail("sun.max", "UV \(Int(uv.rounded()))")
                    }
                    if let air {
                        HStack(spacing: 10) {
                            Circle().fill(Self.colour(air.band)).frame(width: 14, height: 14)
                            Text("AQI \(air.aqi) \(air.shortLabel)")
                        }
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Ink.soft)
                    }
                }
            }
            .padding(.top, 18)
            ForEach(weather.alerts.prefix(2), id: \.self) { alert in
                Label(alert.event, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Ink.amber)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Ink.amber.opacity(0.16), in: Capsule())
                    .padding(.top, 14)
            }
        }
    }

    private func detail(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 26, weight: .medium))
            .foregroundStyle(Ink.soft)
            .monospacedDigit()
    }

    static func colour(_ band: AirQuality.Band) -> Color {
        switch band {
        case .good: return Color.p3(0.36, 0.85, 0.45)
        case .moderate: return Color.p3(0.98, 0.84, 0.3)
        case .sensitive: return Color.p3(1.0, 0.6, 0.25)
        case .unhealthy: return Color.p3(0.95, 0.3, 0.3)
        case .veryUnhealthy: return Color.p3(0.7, 0.35, 0.75)
        case .hazardous: return Color.p3(0.6, 0.15, 0.25)
        }
    }
}

// MARK: - On the ground

/// The temperature from a degree reading, coloured by how it feels: ice blue through mint
/// and gold to red.
private enum Heat {
    private static let stops: [(c: Double, rgb: RGB)] = [
        (-10, RGB(0.6, 0.72, 1.0)),
        (0, RGB(0.45, 0.8, 1.0)),
        (9, RGB(0.42, 0.92, 0.78)),
        (17, RGB(0.98, 0.88, 0.42)),
        (25, RGB(1.0, 0.62, 0.3)),
        (33, RGB(1.0, 0.36, 0.32)),
    ]

    static func colour(_ temp: Double, isMetric: Bool) -> Color {
        let c = isMetric ? temp : (temp - 32) * 5 / 9
        if c <= stops[0].c { return stops[0].rgb.color }
        for (a, b) in zip(stops, stops.dropFirst()) where c <= b.c {
            return a.rgb.mix(b.rgb, (c - a.c) / (b.c - a.c)).color
        }
        return stops[stops.count - 1].rgb.color
    }
}

/// The next 24 hours: the weather now, then every three hours, as a line through the
/// temperatures coloured by the heat, with the sky and the chance of rain above each point
/// and sunrise and sunset where they fall.
private struct Ribbon: View {
    let points: [Skylight.Point]
    let sunTimes: [(time: Date, rise: Bool)]
    let isMetric: Bool
    let zone: TimeZone

    /// The band the line moves in, below the symbols and labels.
    private let top: CGFloat = 92
    private let lineHeight: CGFloat = 46

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let places = xs(width)
            let ys = self.ys()
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    guard points.count > 1 else { return }
                    let curve = smoothPath(zip(places, ys).map { CGPoint(x: $0, y: $1) })
                    let gradient = Gradient(stops: points.enumerated().map { i, p in
                        .init(color: Heat.colour(p.temp, isMetric: isMetric), location: places[i] / width)
                    })
                    let shading = GraphicsContext.Shading.linearGradient(
                        gradient, startPoint: .zero, endPoint: CGPoint(x: width, y: 0))
                    var glow = context
                    glow.addFilter(.blur(radius: 10))
                    glow.opacity = 0.7
                    glow.stroke(curve, with: shading, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    context.stroke(curve, with: shading, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    for (i, p) in points.enumerated() {
                        let r: CGFloat = p.isNow ? 9 : 6
                        let dot = Path(ellipseIn: CGRect(x: places[i] - r, y: ys[i] - r, width: r * 2, height: r * 2))
                        context.fill(dot, with: .color(p.isNow ? .white : .black))
                        context.stroke(dot, with: .color(Heat.colour(p.temp, isMetric: isMetric)), lineWidth: 3)
                    }
                    // Sunrise and sunset, as hairlines through the band.
                    for mark in sunMarks(places) {
                        var line = Path()
                        line.move(to: CGPoint(x: mark.x, y: top - 6))
                        line.addLine(to: CGPoint(x: mark.x, y: top + lineHeight + 40))
                        context.stroke(line, with: .color(Ink.amber.opacity(0.5)),
                                       style: StrokeStyle(lineWidth: 1.5, dash: [3, 5]))
                    }
                }
                ForEach(Array(points.enumerated()), id: \.offset) { i, p in
                    column(p)
                        .frame(width: 150)
                        .position(x: places[i], y: 0)
                        .offset(y: 30)
                    Text("\(Int(p.temp.rounded()))°")
                        .font(.system(size: 30, weight: p.isNow ? .semibold : .medium))
                        .monospacedDigit()
                        .foregroundStyle(Ink.text)
                        .position(x: places[i], y: ys[i] + 34)
                    Text(p.isNow ? "Now" : CompactTime.string(p.time, in: zone))
                        .font(.system(size: 24, weight: p.isNow ? .bold : .medium))
                        .foregroundStyle(p.isNow ? Ink.text : Ink.faint)
                        .position(x: places[i], y: top + lineHeight + 72)
                }
                ForEach(Array(sunMarks(places).enumerated()), id: \.offset) { _, mark in
                    Label(CompactTime.string(mark.time, in: zone), systemImage: mark.rise ? "sunrise.fill" : "sunset.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .symbolRenderingMode(.multicolor)
                        .foregroundStyle(Ink.amber.opacity(0.9))
                        .fixedSize()
                        .position(x: mark.x, y: top + lineHeight + 72)
                        .opacity(nearPoint(mark.x, places) ? 0 : 1)
                }
            }
        }
    }

    /// The symbol and the chance of rain above a point.
    private func column(_ p: Skylight.Point) -> some View {
        VStack(spacing: 2) {
            Image(systemName: WeatherSymbol.name(for: p.icon))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 40))
                .frame(height: 48)
            Text(p.precipChance >= 0.2 ? "\(Int((p.precipChance * 100).rounded()))%" : " ")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Ink.rain)
        }
    }

    /// Evenly spaced, inset so the end labels stay on screen.
    private func xs(_ width: CGFloat) -> [CGFloat] {
        guard points.count > 1 else { return [width / 2] }
        let inset: CGFloat = 40
        let step = (width - 2 * inset) / CGFloat(points.count - 1)
        return points.indices.map { inset + CGFloat($0) * step }
    }

    private func ys() -> [CGFloat] {
        let temps = points.map(\.temp)
        guard let lo = temps.min(), let hi = temps.max() else { return [] }
        let span = max(hi - lo, isMetric ? 4 : 8)
        let mid = (hi + lo) / 2
        return temps.map { top + lineHeight * CGFloat(0.5 - ($0 - mid) / span) }
    }

    /// Sunrises and sunsets inside the ribbon's span, placed by time between the points.
    private func sunMarks(_ xs: [CGFloat]) -> [(x: CGFloat, time: Date, rise: Bool)] {
        guard let first = points.first?.time, let last = points.last?.time else { return [] }
        var marks: [(CGFloat, Date, Bool)] = []
        for (t, rise) in sunTimes where t > first && t < last {
            if let x = x(for: t, xs) { marks.append((x, t, rise)) }
        }
        return marks
    }

    private func x(for t: Date, _ xs: [CGFloat]) -> CGFloat? {
        for i in 0..<(points.count - 1) where t >= points[i].time && t <= points[i + 1].time {
            let f = t.timeIntervalSince(points[i].time) / points[i + 1].time.timeIntervalSince(points[i].time)
            return xs[i] + (xs[i + 1] - xs[i]) * CGFloat(f)
        }
        return nil
    }

    /// Too close to a point's hour label to label alongside it.
    private func nearPoint(_ x: CGFloat, _ xs: [CGFloat]) -> Bool {
        xs.contains { abs($0 - x) < 70 }
    }

    /// A Catmull-Rom curve through the points, so the line reads as a smooth day.
    private func smoothPath(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(i - 1, 0)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(i + 2, pts.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }
}

/// The days ahead: name, sky, high and low, and a bar of each day's range against the week's.
private struct Outlook: View {
    let days: [DayForecast]
    let now: Date
    let zone: TimeZone
    let isMetric: Bool

    var body: some View {
        let lo = days.map(\.low).min() ?? 0
        let hi = days.map(\.high).max() ?? 1
        HStack(alignment: .top, spacing: 18) {
            ForEach(days, id: \.self) { day in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Text(name(day.date))
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Ink.text)
                        Spacer(minLength: 0)
                        // One box for every symbol: a tall one (rain under a cloud) pushed its
                        // day's bar and figures below the others'.
                        Image(systemName: WeatherSymbol.name(for: day.icon))
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 28))
                            .frame(width: 40, height: 32)
                    }
                    .frame(height: 32)
                    RangeBar(low: day.low, high: day.high, weekLow: lo, weekHigh: hi, isMetric: isMetric)
                        .frame(height: 6)
                    HStack {
                        Text("\(Int(day.high.rounded()))°").foregroundStyle(Ink.text)
                        Spacer(minLength: 0)
                        Text("\(Int(day.low.rounded()))°").foregroundStyle(Ink.faint)
                    }
                    .font(.system(size: 24, weight: .medium))
                    .monospacedDigit()
                }
                .frame(width: 140)
            }
        }
    }

    private func name(_ date: CivilDate) -> String {
        if date == CivilDate(now, in: zone) { return "Today" }
        return date.start(in: zone).formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated))
    }
}

private struct RangeBar: View {
    let low: Double
    let high: Double
    let weekLow: Double
    let weekHigh: Double
    let isMetric: Bool

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let span = max(weekHigh - weekLow, 1)
            let x0 = w * CGFloat((low - weekLow) / span)
            let x1 = w * CGFloat((high - weekLow) / span)
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.text.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(colors: [Heat.colour(low, isMetric: isMetric), Heat.colour(high, isMetric: isMetric)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(x1 - x0, 6))
                    .offset(x: x0)
            }
        }
    }
}

/// Sunrise, sunset and the day's length; the moon's phase and when the next full or new moon
/// is; when the weather was last read.
private struct SunAndMoon: View {
    let snapshot: Snapshot
    let now: Date

    var body: some View {
        let zone = snapshot.timeZone
        let sun = SunModel(snapshot: snapshot)
        let today = CivilDate(now, in: zone)
        VStack(alignment: .trailing, spacing: 12) {
            if let (rise, set) = LightCycle.daylight(snapshot, sun: sun, on: today) {
                HStack(spacing: 26) {
                    Label(CompactTime.string(rise, in: zone), systemImage: "sunrise.fill")
                    Label(CompactTime.string(set, in: zone), systemImage: "sunset.fill")
                    Text(LightCycle.formatLength(set.timeIntervalSince(rise)))
                        .foregroundStyle(Ink.faint)
                }
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Ink.soft)
            }
            if let moon = snapshot.moon, let day = moon.today {
                HStack(spacing: 14) {
                    MoonDisc(fraction: day.fraction, radius: 15)
                    Text(moon.phaseName)
                        .foregroundStyle(Ink.soft)
                    Text("\(moon.next.isFull ? "Full" : "New") \(moon.next.days == 0 ? "today" : "in \(moon.next.days) d")")
                        .foregroundStyle(Ink.faint)
                }
                .font(.system(size: 26, weight: .medium))
            }
            let stamp = snapshot.sources.weather?.fetchedAt ?? snapshot.generatedAt
            Text("Updated \(CompactTime.string(stamp, in: zone))")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Ink.faint)
        }
    }
}
