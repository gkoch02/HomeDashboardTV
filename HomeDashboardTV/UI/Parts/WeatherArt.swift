import DashboardCore
import SwiftUI

/// The weather painted at full resolution from `WeatherScene`'s composition: gradient skies, a
/// glowing sun, shaded clouds, and at night the real moon photograph at tonight's phase.
/// Static (no motion, for the GPU and the panel), and Equatable on what it draws, so the
/// minute ticks never repaint it. The defaults are the Agenda plate's inks.
struct WeatherArt: View, Equatable {
    let icon: String
    let moonFraction: Double?
    let size: CGSize
    /// Starlight, snow, mist and the moon's glow.
    var light = Color(red: 0.925, green: 0.895, blue: 0.835)
    /// The sun's rim, the lightning and the ring round the moon.
    var accent = Color.p3(0.92, 0.69, 0.22)

    var body: some View {
        let scene = WeatherScene(icon: icon, size: size)
        ZStack(alignment: .topLeading) {
            Canvas(rendersAsynchronously: false) { context, _ in
                sky(scene, in: &context)
                if scene.night { stars(scene, in: &context) }
                if !scene.night { sun(scene, in: &context) }
                if scene.night, let (c, r) = scene.body { moonGlow(c, r, in: &context) }
            }
            if scene.night, let (c, r) = scene.body {
                // Tonight's moon, from the photograph, at the phase the Pi reports.
                ZStack {
                    Circle().stroke(accent.opacity(0.45), lineWidth: max(2, r * 0.02)).padding(-r * 0.06)
                    MoonDisc(fraction: moonFraction ?? 0.5, radius: r)
                }
                .frame(width: r * 2, height: r * 2)
                .position(c)
            }
            Canvas(rendersAsynchronously: false) { context, _ in
                weather(scene, in: &context)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: Sky

    private func palette(_ scene: WeatherScene) -> (top: Color, bottom: Color) {
        if scene.night {
            return (Color(red: 0.03, green: 0.04, blue: 0.09), Color(red: 0.09, green: 0.12, blue: 0.22))
        }
        switch scene.kind {
        case .clear, .fewClouds:
            return (Color(red: 0.07, green: 0.15, blue: 0.28), Color(red: 0.20, green: 0.32, blue: 0.45))
        case .clouds:
            return (Color(red: 0.10, green: 0.15, blue: 0.23), Color(red: 0.24, green: 0.31, blue: 0.39))
        case .mist:
            return (Color(red: 0.17, green: 0.19, blue: 0.22), Color(red: 0.32, green: 0.34, blue: 0.36))
        case .overcast, .snow:
            return (Color(red: 0.15, green: 0.18, blue: 0.22), Color(red: 0.30, green: 0.34, blue: 0.39))
        case .rain:
            return (Color(red: 0.10, green: 0.13, blue: 0.17), Color(red: 0.22, green: 0.27, blue: 0.32))
        case .thunder:
            return (Color(red: 0.07, green: 0.08, blue: 0.11), Color(red: 0.17, green: 0.19, blue: 0.25))
        }
    }

    private func sky(_ scene: WeatherScene, in context: inout GraphicsContext) {
        let (top, bottom) = palette(scene)
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(Gradient(colors: [top, bottom]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height))
        )
    }

    private func stars(_ scene: WeatherScene, in context: inout GraphicsContext) {
        guard scene.kind != .snow else { return }
        var random = SplitMix(seed: 0x5354_4152)  // "STAR"
        let clouds = cloudPath(scene)
        for _ in 0..<140 {
            let p = CGPoint(x: random.unit() * size.width, y: random.unit() * size.height * 0.9)
            let r = 0.6 + pow(random.unit(), 3) * 2.4
            let alpha = 0.25 + random.unit() * 0.6
            guard !clouds.contains(p) else { continue }
            let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            if r > 2 {
                var glow = context
                glow.addFilter(.blur(radius: r * 2))
                glow.fill(dot, with: .color(light.opacity(alpha * 0.6)))
            }
            context.fill(dot, with: .color(light.opacity(alpha)))
        }
    }

    // MARK: Sun and moon

    private func sun(_ scene: WeatherScene, in context: inout GraphicsContext) {
        guard let (c, r) = scene.body else { return }
        let dimmed = scene.kind == .mist ? 0.55 : 1.0
        // The glow, then the rays as beams of light fading outward, then the disc.
        context.fill(
            Path(ellipseIn: CGRect(x: c.x - r * 3, y: c.y - r * 3, width: r * 6, height: r * 6)),
            with: .radialGradient(
                Gradient(colors: [Color.p3(0.98, 0.62, 0.20).opacity(0.30 * dimmed), accent.opacity(0)]),
                center: c, startRadius: r * 0.95, endRadius: r * 2.3
            )
        )
        for wedge in scene.rays {
            var beam = Path()
            beam.move(to: wedge[0])
            for p in wedge.dropFirst() { beam.addLine(to: p) }
            beam.closeSubpath()
            context.fill(beam, with: .linearGradient(
                Gradient(colors: [Color.p3(1, 0.86, 0.55).opacity(0.7 * dimmed), Color.p3(0.98, 0.62, 0.20).opacity(0)]),
                startPoint: c, endPoint: wedge[1]
            ))
        }
        let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        context.fill(disc, with: .radialGradient(
            Gradient(colors: [
                Color.p3(1, 0.97, 0.86).opacity(dimmed),
                Color.p3(0.99, 0.84, 0.47).opacity(dimmed),
                accent.opacity(dimmed),
            ]),
            center: CGPoint(x: c.x - r * 0.25, y: c.y - r * 0.25), startRadius: 0, endRadius: r * 1.15
        ))
    }

    private func moonGlow(_ c: CGPoint, _ r: CGFloat, in context: inout GraphicsContext) {
        context.fill(
            Path(ellipseIn: CGRect(x: c.x - r * 2.6, y: c.y - r * 2.6, width: r * 5.2, height: r * 5.2)),
            with: .radialGradient(
                Gradient(colors: [light.opacity(0.16), light.opacity(0)]),
                center: c, startRadius: r, endRadius: r * 2.6
            )
        )
    }

    // MARK: Cloud, rain, snow, lightning, mist

    private func cloudPath(_ scene: WeatherScene) -> Path {
        var path = Path()
        for (c, r) in scene.puffs { path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)) }
        return path
    }

    private func cloudColors(_ scene: WeatherScene) -> (lit: Color, shade: Color) {
        if scene.night { return (Color(red: 0.36, green: 0.39, blue: 0.47), Color(red: 0.16, green: 0.18, blue: 0.24)) }
        switch scene.kind {
        case .rain: return (Color(red: 0.62, green: 0.66, blue: 0.71), Color(red: 0.27, green: 0.30, blue: 0.36))
        case .thunder: return (Color(red: 0.48, green: 0.51, blue: 0.57), Color(red: 0.17, green: 0.18, blue: 0.23))
        case .overcast, .snow: return (Color(red: 0.80, green: 0.81, blue: 0.82), Color(red: 0.42, green: 0.45, blue: 0.50))
        default: return (Color(red: 0.98, green: 0.97, blue: 0.95), Color(red: 0.62, green: 0.67, blue: 0.74))
        }
    }

    private func weather(_ scene: WeatherScene, in context: inout GraphicsContext) {
        let unit = min(size.width, size.height)
        var random = SplitMix(seed: 0x5745_4154)  // "WEAT"

        if scene.kind == .mist {
            var bands = context
            bands.addFilter(.blur(radius: unit * 0.03))
            for i in 0..<7 {
                let y = size.height * (0.18 + Double(i) * 0.12)
                let inset = size.width * (0.05 + random.unit() * 0.25)
                let band = Path(roundedRect: CGRect(x: inset, y: y, width: size.width - inset * 1.3, height: unit * 0.045), cornerRadius: unit * 0.02)
                bands.fill(band, with: .color(light.opacity(0.10 + random.unit() * 0.12)))
            }
        }

        if scene.kind == .rain || scene.kind == .thunder {
            var rain = Path()
            let base = scene.cloudBase - unit * 0.04
            for _ in 0..<220 {
                let x = random.unit() * (size.width + unit * 0.3) - unit * 0.15
                let y = base + random.unit() * (size.height - base)
                let length = unit * (0.04 + random.unit() * 0.05)
                rain.move(to: CGPoint(x: x, y: y))
                rain.addLine(to: CGPoint(x: x - length * 0.3, y: y + length))
            }
            context.stroke(rain, with: .color(Color(red: 0.74, green: 0.83, blue: 0.92).opacity(0.5)),
                           style: StrokeStyle(lineWidth: max(1.6, unit * 0.0035), lineCap: .round))
        }

        if !scene.puffs.isEmpty {
            let cloud = cloudPath(scene)
            let bounds = cloud.boundingRect
            let (lit, shade) = cloudColors(scene)
            // A soft shadow under the bank, then the bank shaded top to bottom, then a
            // brighter crown on each puff for volume.
            var under = context
            under.addFilter(.blur(radius: unit * 0.035))
            under.fill(cloud.offsetBy(dx: 0, dy: unit * 0.03), with: .color(.black.opacity(0.28)))
            context.fill(cloud, with: .linearGradient(
                Gradient(colors: [lit, shade]),
                startPoint: CGPoint(x: bounds.midX, y: bounds.minY),
                endPoint: CGPoint(x: bounds.midX, y: bounds.maxY)
            ))
            var crowns = context
            crowns.clip(to: cloud)
            crowns.addFilter(.blur(radius: unit * 0.02))
            for (c, r) in scene.puffs {
                crowns.fill(
                    Path(ellipseIn: CGRect(x: c.x - r * 0.7, y: c.y - r * 0.95, width: r * 1.4, height: r * 1.0)),
                    with: .color(lit.opacity(0.55))
                )
            }
        }

        let bolt = scene.bolt
        if let first = bolt.first {
            var path = Path()
            path.move(to: first)
            for p in bolt.dropFirst() { path.addLine(to: p) }
            path.closeSubpath()
            var glow = context
            glow.addFilter(.blur(radius: unit * 0.03))
            glow.fill(path, with: .color(accent.opacity(0.8)))
            context.fill(path, with: .linearGradient(
                Gradient(colors: [Color.p3(1, 0.95, 0.75), accent]),
                startPoint: path.boundingRect.origin,
                endPoint: CGPoint(x: path.boundingRect.maxX, y: path.boundingRect.maxY)
            ))
        }

        if scene.kind == .snow {
            let base = scene.cloudBase - unit * 0.02
            for _ in 0..<130 {
                let p = CGPoint(x: random.unit() * size.width, y: base + random.unit() * (size.height - base))
                let depth = random.unit()
                let r = unit * (0.003 + depth * 0.009)
                let flake = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                var soft = context
                if depth < 0.4 { soft.addFilter(.blur(radius: r * 0.8)) }
                soft.fill(flake, with: .color(light.opacity(0.55 + depth * 0.45)))
            }
        }
    }
}
