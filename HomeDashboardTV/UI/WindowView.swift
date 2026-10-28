import CoreText
import DashboardCore
import SwiftUI

/// A layout drawn for the TV rather than ported from the Pi: a pane of glass with the weather
/// on it, and nothing but light beyond, with the day set over it.
///
/// The pane is a Metal shader running at 30 frames a second (`WindowPane.metal`, drawn by
/// `SkyLayer`, so on an HDR output the lights beyond the glass pass white). Beyond the
/// glass, far out of focus, is colour for the hour and the weather, washes of glow drifting
/// slowly across it and a scatter of lights swaying with the wind; it never pretends to be a
/// place. On the glass: rain leaves beads and sends drops running down, leaning with the wind,
/// and each bead and drop brings the lights behind it into focus as points, upside down; frost
/// creeps in from the edges below freezing, snow catches as flakes, fog and damp air mist it.
/// The biggest, warmest lights are lanterns that stand for what's next, one each, in the
/// colours of the dots beside the list.
///
/// Over the glass: the date, the time and the weather at the top left; what's next at the
/// bottom right.
///
/// As the layout appears the lights come up out of the dark, and the text rises in.
struct WindowView: Theme {
    let snapshot: Snapshot
    let now: Date

    @State private var build = WindowBuild.start

    private var zone: TimeZone { snapshot.timeZone }

    var body: some View {
        ZStack {
            ClockBlock(snapshot: snapshot, now: now)
                .opacity(build.clock)
                .offset(y: (1 - build.clock) * 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            UpNext(snapshot: snapshot, now: now, rise: build.list)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 16)
        // After the lights have begun to come up (WindowBackdrop's own build-in).
        .onBuildIn(reset: { settled in build = settled ? .settled : .start }) {
            withAnimation(.easeOut(duration: 0.9).delay(1.0)) { build.clock = 1 }
            withAnimation(.linear(duration: 1.2).delay(1.3)) { build.list = 1 }
        }
    }

    var backdrop: some View { WindowBackdrop(snapshot: snapshot, now: now) }

    func notice(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.arrow.circlepath")
            .font(.custom(Face.text, size: 22).weight(.medium))
            .foregroundStyle(Ink.ochre)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.black.opacity(0.55), in: Capsule())
    }
}

/// How far the text's build-in has got, each part 0 to 1.
private struct WindowBuild {
    var clock: Double
    var list: Double

    static let start = WindowBuild(clock: 0, list: 0)
    static let settled = WindowBuild(clock: 1, list: 1)
}

private enum Ink {
    static let cream = Color(red: 0.937, green: 0.902, blue: 0.831)
    static let soft = Color(red: 0.81, green: 0.77, blue: 0.68)
    static let faint = Color(red: 0.73, green: 0.68, blue: 0.6)
    static let ochre = Color.p3(0.9, 0.72, 0.36)

    /// The lanterns, warm and each a little different, and the dots that match them.
    static let lamps: [RGB] = [
        RGB(1.0, 0.73, 0.38),
        RGB(1.0, 0.81, 0.51),
        RGB(1.0, 0.67, 0.35),
        RGB(0.98, 0.62, 0.44),
    ]
}

private enum Face {
    static let display = "Cormorant Garamond"
    static let text = "DMSans-9ptRegular"

    /// Cormorant with lining figures: its default old-style ones set the time's 1 as an I.
    static func figures(_ size: CGFloat, weight: PlatformFont.Weight) -> Font {
        .descriptor([
            kCTFontFamilyNameAttribute: display,
            kCTFontTraitsAttribute: [kCTFontWeightTrait: weight.rawValue],
            kCTFontFeatureSettingsAttribute: [[kCTFontFeatureTypeIdentifierKey: kNumberCaseType,
                                               kCTFontFeatureSelectorIdentifierKey: kUpperCaseNumbersSelector]],
        ], size: size)
    }
}

/// The text's shadow, so it holds over the bright lights behind it.
private extension View {
    func lifted() -> some View { shadow(color: .black.opacity(0.7), radius: 14, y: 2) }
}

// MARK: - The pane

/// The shader pane behind the drifting text. Its colours change with the minute; its motion
/// runs on its own timeline, so only this layer redraws thirty times a second.
private struct WindowBackdrop: View {
    let snapshot: Snapshot
    let now: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(DashboardStore.self) private var store
    @State private var lights = Lights.off

    var body: some View {
        let glass = WindowPane.glass(snapshot, now: now)
        let lamps = WindowPane.lamps(snapshot, now: now)
        let count = lamps.events.count + (lamps.birthday == nil ? 0 : 1)
        let palette = Palette(glass: glass)
        let drift = BurnIn.drift(at: now)
        SkyLayer(fragment: "windowPane", paused: reduceMotion, highlights: store.highlights) { frame in
            let time = Float(frame.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600))
            return WindowUniforms(
                frame: frame.header(time: time),
                zenith: palette.zenith.vector, horizon: palette.horizon.vector, ground: palette.ground.vector,
                glow: palette.glow.vector, lights: palette.lights.vector,
                light: SIMD4(Float(palette.night), frame.headroom, glass.storm ? 1 : 0, Float(lights.level(at: frame.date))),
                glass: SIMD4(Float(glass.wet), Float(glass.drift), Float(glass.frost), Float(glass.mist)),
                extra: SIMD4(Float(glass.snow), Float(count), 0, 0),
                lamp0: Ink.lamps[0].vector, lamp1: Ink.lamps[1].vector,
                lamp2: Ink.lamps[2].vector, lamp3: Ink.lamps[3].vector,
                motion: SIMD4(0, 0, Float(drift.width), Float(drift.height)))
        }
        .background(Color.black)
        .onBuildIn(reset: { settled in lights = settled ? .on : .off }) {
            lights = .coming(.now)
        }
    }
}

/// `WindowPane.metal`'s inputs, field for field.
private struct WindowUniforms {
    var frame: SIMD4<Float>
    var zenith, horizon, ground, glow, lights: SIMD4<Float>
    var light, glass, extra: SIMD4<Float>
    var lamp0, lamp1, lamp2, lamp3: SIMD4<Float>
    var motion: SIMD4<Float>
}

/// The pane's build-in, timed by its own timeline (its shader's inputs do not animate): the
/// light comes up out of the dark.
private enum Lights: Equatable {
    case off, coming(Date), on

    func level(at date: Date) -> Double {
        switch self {
        case .off: return 0
        case .on: return 1
        case .coming(let start):
            let t = min(max((date.timeIntervalSince(start) - 0.2) / 1.8, 0), 1)
            return t * t * (3 - 2 * t)
        }
    }
}

/// The light's colours for the hour and the weather.
private struct Palette {
    var zenith: RGB
    var horizon: RGB
    var ground: RGB
    var glow: RGB
    var lights: RGB
    /// 0 by day to 1 at night.
    var night: Double

    init(glass: WindowPane.Glass) {
        let alt = glass.altitude
        let day = smooth(-8, 8, alt)
        let golden = exp(-pow((alt - 3) / 8, 2))
        night = 1 - day
        // Cloud and rain grey it all; the night keeps a little deep blue.
        let dull = min(1, 0.3 + 0.7 * glass.cover)
        let sky = RGB(SkyColour.rgb(alt)).greyed(dull * 0.6)
        let dusk = RGB(0.035, 0.04, 0.085).scaled(night)
        zenith = sky.scaled(0.6).plus(dusk.scaled(0.6))
        horizon = sky.scaled(0.95).plus(dusk)
        ground = RGB(0.015, 0.016, 0.03).mix(sky.greyed(0.5).scaled(0.42), day)
        // The glow: deep violet at night, pale by day, warm round sunrise and sunset.
        let byDay = RGB(1.0, 0.95, 0.86).greyed(dull * 0.4).scaled(0.5)
        glow = RGB(0.22, 0.17, 0.42).mix(byDay, day).mix(RGB(1.0, 0.55, 0.3).scaled(0.7), golden * 0.8)
        lights = RGB(1.0, 0.72, 0.4)
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
    func plus(_ o: RGB) -> RGB { RGB(r + o.r, g + o.g, b + o.b) }
    func greyed(_ amount: Double) -> RGB {
        let l = 0.3 * r + 0.59 * g + 0.11 * b
        return mix(RGB(l, l, l), amount)
    }
    var color: Color { Color.p3(r, g, b) }
    var vector: SIMD4<Float> { Sky.rgb(color) }
}

// MARK: - Over the glass

/// The date, the time, and the weather now beside the temperature, with any alert.
private struct ClockBlock: View {
    let snapshot: Snapshot
    let now: Date

    var body: some View {
        let zone = snapshot.timeZone
        let clock = ClockTime.parts(now, in: zone)
        VStack(alignment: .leading, spacing: 0) {
            Text(now.formatted(Date.FormatStyle(timeZone: zone).weekday(.wide).day().month(.wide)).uppercased())
                .font(.custom(Face.text, size: 28).weight(.medium))
                .tracking(28 * 0.18)
                .foregroundStyle(Ink.soft)
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(clock.time)
                    .font(Face.figures(230, weight: .light))
                    .foregroundStyle(Ink.cream)
                if let period = clock.period {
                    Text(period)
                        .font(.custom(Face.display, size: 52).weight(.light))
                        .foregroundStyle(Ink.soft)
                }
            }
            .padding(.top, -24)
            if let weather = snapshot.sources.weather?.data {
                WeatherLine(weather: weather, now: now, isMetric: snapshot.isMetric)
                    .padding(.top, -20)
            }
        }
        .lifted()
    }
}

private struct WeatherLine: View {
    let weather: Weather
    let now: Date
    let isMetric: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .center, spacing: 30) {
                // Cormorant's degree sign is a raised o: DM Sans's reads as one.
                (Text("\(Int(weather.currentTemp.rounded()))").font(Face.figures(112, weight: .regular))
                    + Text("°").font(.custom(Face.text, size: 72).weight(.light)))
                    .foregroundStyle(Ink.cream)
                VStack(alignment: .leading, spacing: 6) {
                    Text(sky)
                    Text(details)
                }
                .font(.custom(Face.text, size: 30))
                .foregroundStyle(Ink.soft)
            }
            ForEach(weather.alerts.prefix(2), id: \.self) { alert in
                Text(alert.event.uppercased())
                    .font(.custom(Face.text, size: 24).weight(.medium))
                    .tracking(24 * 0.14)
                    .foregroundStyle(Ink.ochre)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .overlay(Capsule().stroke(Ink.ochre, lineWidth: 2))
            }
        }
    }

    /// "Light rain, 80%": the sky now, and the chance of rain when it's worth saying.
    private var sky: String {
        let chance = Skylight.ribbon(weather, now: now).first?.precipChance ?? 0
        let description = weather.currentDescription.prefix(1).uppercased() + weather.currentDescription.dropFirst()
        return chance >= 0.2 ? "\(description), \(Int((chance * 100).rounded()))%" : description
    }

    /// "Wind NW 12 mph · low 33°".
    private var details: String {
        var parts: [String] = []
        if let speed = weather.windSpeed {
            let compass = weather.windDeg.map { Compass.point($0) + " " } ?? ""
            parts.append("Wind \(compass)\(Int(speed.rounded())) \(isMetric ? "m/s" : "mph")")
        }
        parts.append("low \(Int(weather.low.rounded()))°")
        return parts.joined(separator: " · ")
    }
}

/// What's next, each line with the dot of its lantern behind the glass: the next three events, then
/// under a rule the next birthday within the week.
private struct UpNext: View {
    let snapshot: Snapshot
    let now: Date
    /// The build-in's progress, 0 to 1: the lines rise in one after another.
    let rise: Double

    var body: some View {
        let zone = snapshot.timeZone
        let lamps = WindowPane.lamps(snapshot, now: now)
        VStack(alignment: .leading, spacing: 18) {
            Text("UP NEXT")
                .font(.custom(Face.text, size: 24).weight(.medium))
                .tracking(24 * 0.2)
                .foregroundStyle(Ink.faint)
                .rise(rise, index: 0)
            if lamps.events.isEmpty && lamps.birthday == nil {
                Text("Nothing else on the calendar")
                    .font(.custom(Face.display, size: 40))
                    .foregroundStyle(Ink.soft)
                    .rise(rise, index: 1)
            }
            ForEach(Array(lamps.events.enumerated()), id: \.element) { index, event in
                let live = event.start <= now
                row(lamp: index, when: live ? "Now" : Skylight.when(event, now: now, zone: zone),
                    what: event.summary, live: live)
                    .rise(rise, index: index + 1)
            }
            if let birthday = lamps.birthday {
                Rectangle()
                    .fill(Ink.cream.opacity(0.25))
                    .frame(height: 1)
                    .rise(rise, index: lamps.events.count + 1)
                row(lamp: lamps.events.count, when: day(birthday.date), what: "\(birthday.name)’s birthday", live: false)
                    .rise(rise, index: lamps.events.count + 2)
            }
        }
        .frame(width: 720, alignment: .leading)
        .lifted()
    }

    /// When, small, over what: the title has the column's whole width and may take two lines,
    /// as a real calendar's titles need.
    private func row(lamp: Int, when: String, what: String, live: Bool) -> some View {
        let tint = Ink.lamps[min(lamp, Ink.lamps.count - 1)].color
        return HStack(alignment: .top, spacing: 22) {
            Circle()
                .fill(tint)
                .frame(width: 16, height: 16)
                .shadow(color: tint, radius: 10)
                .padding(.top, 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(when)
                    .font(.custom(Face.text, size: 24))
                    .monospacedDigit()
                    .foregroundStyle(live ? Ink.ochre : Ink.soft)
                    .lineLimit(1)
                Text(what)
                    .font(.custom(Face.display, size: 42).weight(.medium))
                    .foregroundStyle(Ink.cream)
                    .lineLimit(2)
                    .lineSpacing(-6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "Today", "Tomorrow", or the weekday.
    private func day(_ date: CivilDate) -> String {
        let zone = snapshot.timeZone
        let today = CivilDate(now, in: zone)
        if date == today { return "Today" }
        if date == today.adding(days: 1) { return "Tomorrow" }
        return date.start(in: zone).formatted(Date.FormatStyle(timeZone: zone).weekday(.wide))
    }
}
