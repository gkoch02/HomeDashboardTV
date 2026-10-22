import DashboardCore
import SwiftUI

/// A layout drawn for an OLED TV rather than ported from the Pi: an aurora over a lake, on
/// true black, with the day set small along the bottom.
///
/// The sky is a Metal shader running at 30 frames a second (`AuroraSky.metal`, drawn by
/// `SkyLayer`, so on an HDR output the brightest folds pass white): three curtains
/// of light swaying over a line of hills, reflected in the water below, with stars behind.
/// The air sets their colour (`Aurora.curtain`): green with violet tops in good air, warming
/// through amber to red as the AQI climbs, so a bad-air day reads from across the room. The
/// wind sets how restless they are. Almost nothing on the screen holds still, and what does is
/// small, dim and drifts.
///
/// Along the bottom: the time and the weather on the left; the air, the pressure and the wind,
/// then what's next on the calendar, on the right.
///
/// As the layout appears the curtains brighten out of the black, and the text rises in over them.
struct AuroraView: Theme {
    let snapshot: Snapshot
    let now: Date

    @Environment(DashboardStore.self) private var store
    @State private var build = AuroraBuild.start

    private var zone: TimeZone { snapshot.timeZone }

    var body: some View {
        let curtain = Aurora.curtain(aqi: snapshot.sources.airQuality?.data?.aqi)
        HStack(alignment: .bottom, spacing: 60) {
            ClockBlock(snapshot: snapshot, now: now)
                .opacity(build.clock)
                .offset(y: (1 - build.clock) * 20)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                Readings(snapshot: snapshot, now: now, curtain: curtain,
                         previousPressure: store.pressureHistory.previous(now: now))
                    .opacity(build.readings)
                    .offset(y: (1 - build.readings) * 20)
                Coming(snapshot: snapshot, now: now)
                    .opacity(build.coming)
                    .offset(y: (1 - build.coming) * 20)
            }
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // After the curtains have begun to brighten (AuroraSky's own build-in).
        .onBuildIn(reset: { settled in build = settled ? .settled : .start }) {
            withAnimation(.easeOut(duration: 0.9).delay(1.2)) { build.clock = 1 }
            withAnimation(.easeOut(duration: 0.9).delay(1.5)) { build.readings = 1 }
            withAnimation(.easeOut(duration: 0.9).delay(1.8)) { build.coming = 1 }
        }
    }

    var backdrop: some View { AuroraSky(snapshot: snapshot, now: now) }

    func notice(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.arrow.circlepath")
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(Ink.amber)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.black.opacity(0.6), in: Capsule())
    }
}

/// How far the text's build-in has got, each part 0 to 1.
private struct AuroraBuild {
    var clock: Double
    var readings: Double
    var coming: Double

    static let start = AuroraBuild(clock: 0, readings: 0, coming: 0)
    static let settled = AuroraBuild(clock: 1, readings: 1, coming: 1)
}

private enum Ink {
    static let text = Color(red: 0.9, green: 0.93, blue: 0.92)
    static let soft = text.opacity(0.7)
    static let faint = text.opacity(0.48)
    static let amber = Color(red: 1.0, green: 0.76, blue: 0.32)

    /// The curtain's edge colour, lightened to read as text.
    static func air(_ curtain: Aurora.Curtain) -> Color {
        Color(hue: curtain.edge / 360, saturation: 0.5, brightness: 1)
    }
}

// MARK: - The sky

/// The shader sky behind the drifting text. Its colours change with the snapshot; its motion
/// runs on its own timeline, so only this layer redraws thirty times a second.
private struct AuroraSky: View {
    let snapshot: Snapshot
    let now: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = AuroraClock()
    @State private var glow = Glow.dark

    var body: some View {
        let curtain = Aurora.curtain(aqi: snapshot.sources.airQuality?.data?.aqi)
        let unrest = Aurora.unrest(windSpeed: snapshot.sources.weather?.data?.windSpeed, isMetric: snapshot.isMetric)
        let edge = Color(hue: curtain.edge / 360, saturation: 0.88, brightness: 0.95)
        let fringe = Color(hue: curtain.fringe / 360, saturation: 0.8, brightness: 0.8)
        let drift = BurnIn.drift(at: now)
        SkyLayer(fragment: "auroraSky", paused: reduceMotion) { frame in
            let motion = clock.advance(to: frame.date, unrest: unrest)
            return AuroraUniforms(
                frame: frame.header(time: motion.time),
                wave: SIMD4(motion.phase, motion.unrest, Float(glow.light(at: frame.date)), frame.headroom),
                edge: Sky.rgb(edge), fringe: Sky.rgb(fringe),
                motion: SIMD4(0, 0, Float(drift.width), Float(drift.height)))
        }
        .background(Color.black)
        .onBuildIn(reset: { settled in glow = settled ? .shown : .dark }) {
            glow = .rising(.now)
        }
    }
}

/// `AuroraSky.metal`'s inputs, field for field.
private struct AuroraUniforms {
    var frame, wave, edge, fringe, motion: SIMD4<Float>
}

/// The sky's build-in, timed by the sky's own timeline (its shader's inputs do not animate):
/// the curtains brighten out of the black.
private enum Glow: Equatable {
    case dark, rising(Date), shown

    /// How bright the sky is, 0 (black) to 1.
    func light(at date: Date) -> Double {
        switch self {
        case .dark: return 0
        case .shown: return 1
        case .rising(let start):
            let t = min(max((date.timeIntervalSince(start) - 0.3) / 2.4, 0), 1)
            return t * t * (3 - 2 * t)
        }
    }
}

/// The curtains' motion, summed frame by frame: how far their waves have moved, at a speed
/// set by the wind. Summing, rather than multiplying the time by the wind, means a new wind
/// changes their speed and never jumps them to another place; the wind's own value eases over
/// a few seconds for the same reason. The phase wraps at 2π, where the shader's every wave has
/// turned a whole number of times, and the clock for the stars at an hour.
private final class AuroraClock {
    private var last: Date?
    private var phase = 0.0
    private var unrest: Double?

    func advance(to date: Date, unrest target: Double) -> (phase: Float, time: Float, unrest: Float) {
        // A gap (the app in the background, a paused timeline) resumes from where it stopped.
        let dt = last.map { min(max(date.timeIntervalSince($0), 0), 0.25) } ?? 0
        last = date
        let current = unrest.map { $0 + (target - $0) * min(1, dt / 4) } ?? target
        unrest = current
        phase = (phase + dt * (0.03 + 0.07 * current)).truncatingRemainder(dividingBy: 2 * .pi)
        let time = Float(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600))
        return (Float(phase), time, Float(current))
    }
}

// MARK: - The text

/// The date, the time, and the weather now in a line.
private struct ClockBlock: View {
    let snapshot: Snapshot
    let now: Date

    var body: some View {
        let zone = snapshot.timeZone
        let clock = ClockTime.parts(now, in: zone)
        VStack(alignment: .leading, spacing: 0) {
            Text(now.formatted(Date.FormatStyle(timeZone: zone).weekday(.wide).month(.wide).day()).uppercased())
                .font(.system(size: 26, weight: .medium))
                .tracking(26 * 0.2)
                .foregroundStyle(Ink.faint)
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(clock.time)
                    .font(.system(size: 196, weight: .ultraLight))
                    .monospacedDigit()
                    .kerning(-3)
                    .foregroundStyle(Ink.text)
                if let period = clock.period {
                    Text(period)
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(Ink.soft)
                }
            }
            .padding(.top, -10)
            if let weather = snapshot.sources.weather?.data {
                Text("\(Int(weather.currentTemp.rounded()))°  \(weather.currentDescription.capitalized(with: .current))  ·  L \(Int(weather.low.rounded()))°")
                    .font(.system(size: 32, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(Ink.soft)
                    .padding(.top, -6)
            }
        }
    }
}

/// The air in the curtains' colour, then the pressure and its trend, the wind and any alert.
private struct Readings: View {
    let snapshot: Snapshot
    let now: Date
    let curtain: Aurora.Curtain
    let previousPressure: Double?

    var body: some View {
        let weather = snapshot.sources.weather?.data
        VStack(alignment: .trailing, spacing: 12) {
            if let air = snapshot.sources.airQuality?.data {
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    Text("AIR")
                        .font(.system(size: 24, weight: .medium))
                        .tracking(24 * 0.2)
                        .foregroundStyle(Ink.faint)
                    Text("\(air.aqi)")
                        .font(.system(size: 76, weight: .light))
                        .monospacedDigit()
                    Text(air.shortLabel)
                        .font(.system(size: 30, weight: .medium))
                }
                .foregroundStyle(Ink.air(curtain))
            }
            if let pressure = weather?.pressure {
                let trend = Weatherglass.trend(pressure, from: previousPressure).map { ", " + $0.lowercased() } ?? ""
                line("Pressure \(Int(pressure.rounded())) hPa\(trend)")
            }
            if let speed = weather?.windSpeed {
                let compass = weather?.windDeg.map { Compass.point($0) + " " } ?? ""
                line("Wind \(compass)\(Int(speed.rounded())) \(snapshot.isMetric ? "m/s" : "mph")")
            }
            ForEach(weather?.alerts.prefix(2) ?? [], id: \.self) { alert in
                Label(alert.event, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Ink.amber)
            }
        }
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 28, weight: .regular))
            .monospacedDigit()
            .foregroundStyle(Ink.soft)
    }
}

/// Under a hairline: the next two events, and the next birthday within the week.
private struct Coming: View {
    let snapshot: Snapshot
    let now: Date

    var body: some View {
        let zone = snapshot.timeZone
        let events = Skylight.upNext(snapshot, now: now, limit: 2)
        let birthday = nextBirthday
        if !events.isEmpty || birthday != nil {
            VStack(alignment: .trailing, spacing: 12) {
                Rectangle()
                    .fill(Ink.text.opacity(0.18))
                    .frame(width: 380, height: 1)
                    .padding(.vertical, 10)
                ForEach(events, id: \.self) { event in
                    HStack(spacing: 14) {
                        Text(Skylight.when(event, now: now, zone: zone))
                            .foregroundStyle(event.start <= now ? Ink.amber : Ink.soft)
                            .monospacedDigit()
                        Text(event.summary)
                            .foregroundStyle(Ink.text)
                            .lineLimit(1)
                    }
                    .font(.system(size: 28, weight: .regular))
                }
                if let birthday {
                    Text(birthday)
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(Ink.faint)
                }
            }
            .padding(.top, 8)
        }
    }

    /// "Friday · Mom's birthday": the next birthday, if it falls within the week.
    private var nextBirthday: String? {
        let zone = snapshot.timeZone
        let today = CivilDate(now, in: zone)
        guard let next = Agenda.upcomingBirthdays(from: snapshot, now: now).first,
              next.date <= today.adding(days: 6) else { return nil }
        let when = next.date == today ? "Today"
            : next.date == today.adding(days: 1) ? "Tomorrow"
            : next.date.start(in: zone).formatted(Date.FormatStyle(timeZone: zone).weekday(.wide))
        return "\(when) · \(next.name)’s birthday"
    }
}
